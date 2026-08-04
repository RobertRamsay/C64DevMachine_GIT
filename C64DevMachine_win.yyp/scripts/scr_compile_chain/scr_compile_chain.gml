/// @description Walks the node spine(s) and emits a flat instruction list
///              for the assembler. All macro instructions are tagged with
///              the source node id at [2] so Pass 1.5 can accumulate byte
///              counts per node in scr_c64_do_update_addresses.
///
/// SPRITE FIX NOTES (all changes marked [SPR-FIX]):
///   1. MACRO_SPR now reads _bank_addr from asset manager (was hardcoded $6800 fallback).
///   2. _vic_bank and _bank_base are derived from _bank_addr, not assumed to be bank 0.
///   3. CIA $DD00 bank-select write is always emitted so VIC points at the right 16KB bank.
///   4. _spr_ptr is ((_bank_addr - _bank_base) / 64) + frame — relative to VIC bank.
///   5. A fallback guard logs a warning if the asset name cannot be resolved.
///   6. [BITMAP FIX] The pointer register address is now derived at RUNTIME from $D018,
///      not hardcoded at compile time. This means MACRO_SPR always writes to the correct
///      pointer table regardless of which screen RAM address MACRO_BMP (or MACRO_VIC)
///      configured. The emitted sequence reads $D018, extracts bits 7-4 (screen RAM
///      offset), shifts to recover the actual address, adds $03F8+slot, and stores there.
///      Zero-page $FB/$FC are used as scratch (clobbered, documented below).

function scr_compile_chain() {
    var instruction_list = [];
    global.inject_null_sid = false;
    global.coll_row_luts_emitted = false; // reset per compile so row LUTs emit once per build
    global.vbmp_runtime_emitted  = false; // reset per compile so vector-bitmap runtime emits once
    global.print_ext_helpers_emitted = false; // reset per compile so DEC/HEX/BIN helpers emit once
    global.bmpblk_mask_emitted       = false; // reset per compile so MCMASK00 emits once
    global.bmpblk_tone_emitted       = false; // reset per compile so MBBTONE emits once
    global.bmpblk_bit_emitted        = false; // reset per compile so MBBBIT emits once
    global.bmpblk_lut_emitted        = false; // reset per compile so MBB multiply LUTs emit once
    global.math_helpers_emitted      = false; // reset per compile so MATH mul16/div16 emit once
    global.sidsong_notetab_emitted   = false; // reset per compile so the SID song note table emits once
    // Pre-scan: only emit the mul16/div16 helpers if some MATH node actually
    // uses MUL (op 2) or DIV (op 3). Pure ADD/SUB/ONEMINUS/INVSIGN projects
    // then carry zero multiply/divide code.
    global.math_needs_muldiv = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_MATH" && array_length(instructions[0]) > 1) {
            var _mop = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0;
            if (_mop != 2 && _mop != 3) continue;

            // Determine if THIS node's operands are byte-only (mirrors the
            // in-case width decision) to route it to the 8-bit routine.
            var _pin  = string(instructions[0][2]);
            var _pmod = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
            var _plit = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0;
            var _pov  = string(instructions[0][5]);

            var _pin_sz = 1;
            var _pm_in = scr_nloc_find_meta(_pin);
            if (_pm_in != undefined) _pin_sz = _pm_in.size;

            var _pop_byte = true;
            if (_pmod == 1) {
                var _pop_sz = 1;
                var _pm_op = scr_nloc_find_meta(_pov);
                if (_pm_op != undefined) _pop_sz = _pm_op.size;
                _pop_byte = (_pop_sz == 1);
            } else {
                _pop_byte = (_plit >= -128 && _plit <= 127);
            }

            var _pbyte = (_pin_sz == 1) && _pop_byte;
            if (_pbyte && _mop == 2) global.math_needs_mul8 = true;
            else if (_pbyte && _mop == 3) global.math_needs_div8 = true;
            else global.math_needs_muldiv = true; // any word MUL/DIV needs 16-bit
        }
    }
    // =============================================================
    // SAFETY: Bail silently if any ORG is at $0000/$---- with children.
    // The user-facing message lives in the F4/F5 build entry points so it
    // only fires on a real build attempt, not on every address-pass call.
    // =============================================================
    if (array_length(scr_check_org_zero_crash()) > 0) {
        return instruction_list;
    }

    // Force start address so labels and absolute addresses calculate correctly
    array_push(instruction_list, ["org", global.start_pc]);

    // ================================================================
    // SPINE WALKER
    // Traverses nodes top-to-bottom and emits instructions per node type.
    // _start_node : first node in this chain
    // _list       : instruction array to append to
    // _org_ref    : parent ORG node (noone = main spine)
    // ================================================================
	// Set SID IRQ line to just before first MACRO_IRQ raster
var _sid_irq_line = 0x60; // default
with (obj_c64_node) {
    if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone) {
        var _irq_rasters = [];
        with (obj_c64_node) {
            if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone) {
                var _r = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0x60;
                array_push(_irq_rasters, _r);
            }
        }
array_sort(_irq_rasters, function(a, b) { return a - b; });
        // Hardcode to line $10 (16) which is safely in the top border/overscan
      var _sid_node_irq = 0xff;
			with (obj_c64_node) {
			    if (node_type == "MACRO_SID" && is_connected) {
			        if (array_length(instructions[0]) > 4 && is_real(instructions[0][4]))
			            _sid_node_irq = clamp(real(instructions[0][4]), 0, 255);
			        break;
			    }
			}
			_sid_irq_line = _sid_node_irq;
			break;
    }
}
global.sid_irq_line = _sid_irq_line;
   global.coll_prelatch_done = false;
    var _walk_spine = function(_start_node, _list, _org_ref) {
        var _curr  = _start_node;
        var _guard = 0;

        while (instance_exists(_curr) && _guard < 256) {

switch (_curr.node_type) {

// --------------------------------------------------------
// COMMENT / EXECUTE - no output
// --------------------------------------------------------
case "COMMENT":
case "EXECUTE":
break;

// --------------------------------------------------------
// LABEL - emit a label marker (0 bytes)
// --------------------------------------------------------
case "LABEL":
    array_push(_list, ["label",
        string_replace_all(string(_curr.instructions[0][1]), " ", "_")
    ]);
break;
		
		
// --------------------------------------------------------
// MACRO_MATH
// [1] op (0=ADD 1=SUB 2=MUL 3=DIV 4=ONEMINUS 5=INVSIGN)
// [2] in_var  [3] operand_mode(0=LIT 1=VAR)  [4] operand_lit(signed)
// [5] operand_var  [6] result_var
//
// Signed two's complement throughout. Each var's width comes from its
// own meta (byte=1, word=2). ADD/SUB/ONEMINUS/INVSIGN inline; MUL/DIV
// call the shared math_mul16 / math_div16 routines (emit-once).
//
// Working regs (ZP, reused each op — chosen to avoid the macro map at
// $FB-$FE and vector-bmp $D0-$DA): 
//   $F2/$F3 = A operand (in_var, sign-extended to 16)
//   $F4/$F5 = B operand (operand var/lit, sign-extended to 16)
//   $F6/$F7 = result (16-bit) 
//   $F8     = sign scratch for mul/div
// --------------------------------------------------------
case "MACRO_MATH": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _op       = (array_length(_i0) > 1 && is_real(_i0[1])) ? real(_i0[1]) : 0;
    var _in_var   = (array_length(_i0) > 2) ? string(_i0[2]) : "";
    var _op_mode  = (array_length(_i0) > 3 && is_real(_i0[3])) ? real(_i0[3]) : 0;
    var _op_lit   = (array_length(_i0) > 4 && is_real(_i0[4])) ? real(_i0[4]) : 0;
    var _op_var   = (array_length(_i0) > 5) ? string(_i0[5]) : "";
    var _res_var  = (array_length(_i0) > 6) ? string(_i0[6]) : "";

    // ZP working registers
    var _A_LO = 0xF2; var _A_HI = 0xF3;
    var _B_LO = 0xF4; var _B_HI = 0xF5;
    var _R_LO = 0xF6; var _R_HI = 0xF7;
    var _SGN  = 0xF8;

    // ---- resolve addresses + widths (SET_VAR pattern) ----
    var _in_addr = 0; var _in_sz = 1;
    if (ds_map_exists(global.named_loc_map, _in_var)) {
        _in_addr = ds_map_find_value(global.named_loc_map, _in_var);
    }
    if (_in_addr == 0) {
        var _iv_find = _in_var;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _iv_find) {
                other._in_addr = pc_address;
                break;
            }
        }
    }
    var _m_in = scr_nloc_find_meta(_in_var);
    if (_m_in != undefined) _in_sz = _m_in.size;
    if (_in_addr == 0) show_debug_message("MACRO_MATH WARNING: in_var '" + _in_var + "' not resolved.");

    var _res_addr = 0; var _res_sz = 1;
    if (ds_map_exists(global.named_loc_map, _res_var)) {
        _res_addr = ds_map_find_value(global.named_loc_map, _res_var);
    }
    if (_res_addr == 0) {
        var _rv_find = _res_var;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _rv_find) {
                other._res_addr = pc_address;
                break;
            }
        }
    }
    var _m_rs = scr_nloc_find_meta(_res_var);
    if (_m_rs != undefined) _res_sz = _m_rs.size;
    if (_res_addr == 0) show_debug_message("MACRO_MATH WARNING: result_var '" + _res_var + "' not resolved.");

    var _op_addr = 0; var _op_sz = 1;
    if (_op_mode == 1) {
        if (ds_map_exists(global.named_loc_map, _op_var)) {
            _op_addr = ds_map_find_value(global.named_loc_map, _op_var);
        }
        if (_op_addr == 0) {
            var _ov_find = _op_var;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _ov_find) {
                    other._op_addr = pc_address;
                    break;
                }
            }
        }
        var _m_op = scr_nloc_find_meta(_op_var);
        if (_m_op != undefined) _op_sz = _m_op.size;
        if (_op_addr == 0) show_debug_message("MACRO_MATH WARNING: operand_var '" + _op_var + "' not resolved.");
    }

    // ========================================================
    // WIDTH DECISION — pick 8-bit fast path or 16-bit path.
    // 8-bit is valid only for ADD/SUB/ONEMINUS/INVSIGN when every
    // involved var is a byte and (for literal operand) the literal
    // fits a signed byte. MUL/DIV always use the 16-bit routines.
    // ========================================================
    var _lit_fits_byte   = (_op_lit >= -128 && _op_lit <= 127);
    var _operand_is_byte = (_op_mode == 1) ? (_op_sz == 1) : _lit_fits_byte;
    // 8-bit fast path only for ADD/SUB/ONEMINUS/INVSIGN when every var is a
    // byte. MUL/DIV always use the proven 16-bit routines (byte-optimised
    // mul8/div8 not yet implemented — do NOT route MUL/DIV here).
    var _all_byte  = (_in_sz == 1) && (_res_sz == 1) && _operand_is_byte;
    var _use_fast8 = _all_byte && (_op == 0 || _op == 1 || _op == 4 || _op == 5);

    var _mth_pfx = "math_" + string(real(_id)) + "_";

    // ========================================================
    // 8-BIT FAST PATH — single-byte, no sign extension, no helpers.
    // Result is naturally correct two's complement in one byte.
    // ========================================================
    if (_use_fast8) {
        if (_op == 4) {
            // R = 1 - A
            array_push(_list, ["sec",     0, _id]);
            array_push(_list, ["lda_imm", 0x01, _id]);
            array_push(_list, ["sbc_abs", _in_addr, _id]);
        } else if (_op == 5) {
            // R = -A = 0 - A
            array_push(_list, ["sec",     0, _id]);
            array_push(_list, ["lda_imm", 0x00, _id]);
            array_push(_list, ["sbc_abs", _in_addr, _id]);
        } else if (_op == 0) {
            // R = A + B
            array_push(_list, ["clc",     0, _id]);
            array_push(_list, ["lda_abs", _in_addr, _id]);
            if (_op_mode == 1) {
                array_push(_list, ["adc_abs", _op_addr, _id]);
            } else {
                array_push(_list, ["adc_imm", _op_lit & 0xFF, _id]);
            }
        } else {
            // R = A - B
            array_push(_list, ["sec",     0, _id]);
            array_push(_list, ["lda_abs", _in_addr, _id]);
            if (_op_mode == 1) {
                array_push(_list, ["sbc_abs", _op_addr, _id]);
            } else {
                array_push(_list, ["sbc_imm", _op_lit & 0xFF, _id]);
            }
        }
        array_push(_list, ["sta_abs", _res_addr, _id]);
    } else {

    // ========================================================
    // 16-BIT PATH (below) — used for word vars and all MUL/DIV.
    // Load A operand (in_var) into $F2/$F3, sign-extended to 16.
    // ========================================================
    array_push(_list, ["lda_abs", _in_addr, _id]);
    array_push(_list, ["sta_zp",  _A_LO, _id]);
    if (_in_sz >= 2) {
        array_push(_list, ["lda_abs", _in_addr + 1, _id]);
        array_push(_list, ["sta_zp",  _A_HI, _id]);
    } else {
        // sign-extend byte: hi = (A & $80) ? $FF : $00
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  _A_HI, _id]);
        array_push(_list, ["lda_zp",  _A_LO, _id]);
        array_push(_list, ["and_imm", 0x80, _id]);
        array_push(_list, ["beq",     _mth_pfx + "a_pos", _id]);
        array_push(_list, ["lda_imm", 0xFF, _id]);
        array_push(_list, ["sta_zp",  _A_HI, _id]);
        array_push(_list, ["label",   _mth_pfx + "a_pos"]);
    }

    // ========================================================
    // ONEMINUS / INVSIGN — single input, no B operand.
    // ONEMINUS: result = 1 - A  ->  negate A then +1  ==  (~A)+1+1... 
    //   cleaner: R = 1 - A  =>  R = 1 + (-A). Two's comp of A is (~A)+1,
    //   so 1 + (~A) + 1. Implement as: R = 1; R -= A (16-bit sub).
    // INVSIGN: result = -A = (~A)+1.
    // ========================================================
    if (_op == 4) {
        // R = 1 - A
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x01, _id]);
        array_push(_list, ["sbc_zp",  _A_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
    } else if (_op == 5) {
        // R = -A  = (~A) + 1
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
    } else {
        // ====================================================
        // Two-input ops — load B operand into $F4/$F5, signed 16.
        // ====================================================
        if (_op_mode == 1) {
            // from var
            array_push(_list, ["lda_abs", _op_addr, _id]);
            array_push(_list, ["sta_zp",  _B_LO, _id]);
            if (_op_sz >= 2) {
                array_push(_list, ["lda_abs", _op_addr + 1, _id]);
                array_push(_list, ["sta_zp",  _B_HI, _id]);
            } else {
                array_push(_list, ["lda_imm", 0x00, _id]);
                array_push(_list, ["sta_zp",  _B_HI, _id]);
                array_push(_list, ["lda_zp",  _B_LO, _id]);
                array_push(_list, ["and_imm", 0x80, _id]);
                array_push(_list, ["beq",     _mth_pfx + "b_pos", _id]);
                array_push(_list, ["lda_imm", 0xFF, _id]);
                array_push(_list, ["sta_zp",  _B_HI, _id]);
                array_push(_list, ["label",   _mth_pfx + "b_pos"]);
            }
        } else {
            // literal — already sign-correct 16-bit from the editor
            var _lit16 = _op_lit;
            if (_lit16 < 0) _lit16 = 65536 + _lit16; // to unsigned 16-bit pattern
            array_push(_list, ["lda_imm", _lit16 & 0xFF, _id]);
            array_push(_list, ["sta_zp",  _B_LO, _id]);
            array_push(_list, ["lda_imm", (_lit16 >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  _B_HI, _id]);
        }

        if (_op == 0) {
            // ADD: R = A + B  (16-bit)
            array_push(_list, ["clc",    0, _id]);
            array_push(_list, ["lda_zp", _A_LO, _id]);
            array_push(_list, ["adc_zp", _B_LO, _id]);
            array_push(_list, ["sta_zp", _R_LO, _id]);
            array_push(_list, ["lda_zp", _A_HI, _id]);
            array_push(_list, ["adc_zp", _B_HI, _id]);
            array_push(_list, ["sta_zp", _R_HI, _id]);
        } else if (_op == 1) {
            // SUB: R = A - B  (16-bit)
            array_push(_list, ["sec",    0, _id]);
            array_push(_list, ["lda_zp", _A_LO, _id]);
            array_push(_list, ["sbc_zp", _B_LO, _id]);
            array_push(_list, ["sta_zp", _R_LO, _id]);
            array_push(_list, ["lda_zp", _A_HI, _id]);
            array_push(_list, ["sbc_zp", _B_HI, _id]);
            array_push(_list, ["sta_zp", _R_HI, _id]);
        } else if (_op == 2) {
            // MUL: signed 16x16 -> 16 (truncated) via shared routine
            global.math_needs_muldiv = true;
            array_push(_list, ["jsr", "math_mul16", _id]);
        } else {
            // DIV: signed 16/16 -> 16 (trunc toward zero) via shared routine
            global.math_needs_muldiv = true;
            array_push(_list, ["jsr", "math_div16", _id]);
        }
    }

    // ========================================================
    // Store result into result_var at its own width (truncate).
    // ========================================================
    array_push(_list, ["lda_zp",  _R_LO, _id]);
    array_push(_list, ["sta_abs", _res_addr, _id]);
    if (_res_sz >= 2) {
        array_push(_list, ["lda_zp",  _R_HI, _id]);
        array_push(_list, ["sta_abs", _res_addr + 1, _id]);
    }

    } // end 16-bit path (else of _use_fast8)

    // ════════════════════════════════════════════════════════════════
    // SHARED HELPERS — math_mul16 / math_div16, emitted once, jumped over
    // ════════════════════════════════════════════════════════════════
    if (global.math_needs_muldiv && !global.math_helpers_emitted) {
        global.math_helpers_emitted = true;

        array_push(_list, ["jmp_abs", "math_helpers_skip", _id]);

        // ────────────────────────────────────────────────────────────
        // math_mul16 — signed 16x16 -> 16 (low word, truncated).
        // In:  $F2/$F3 = A,  $F4/$F5 = B
        // Out: $F6/$F7 = product (low 16 bits)
        // Method: take |A|,|B| via two's comp if bit15 set, track sign
        //   parity in $F8 bit0, unsigned shift-add into $F6/$F7, then
        //   negate result if signs differed. Clobbers A,X,Y.
        // ────────────────────────────────────────────────────────────
        array_push(_list, ["label", "math_mul16"]);
        // sign parity = 0
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  _SGN, _id]);
        // if A negative: flip parity, negate A
        array_push(_list, ["lda_zp",  _A_HI, _id]);
        array_push(_list, ["and_imm", 0x80, _id]);
        array_push(_list, ["beq",     "math_mul16_apos", _id]);
        array_push(_list, ["inc_zp",  _SGN, _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_LO, _id]);
        array_push(_list, ["sta_zp",  _A_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_HI, _id]);
        array_push(_list, ["sta_zp",  _A_HI, _id]);
        array_push(_list, ["label",   "math_mul16_apos"]);
        // if B negative: flip parity, negate B
        array_push(_list, ["lda_zp",  _B_HI, _id]);
        array_push(_list, ["and_imm", 0x80, _id]);
        array_push(_list, ["beq",     "math_mul16_bpos", _id]);
        array_push(_list, ["inc_zp",  _SGN, _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _B_LO, _id]);
        array_push(_list, ["sta_zp",  _B_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _B_HI, _id]);
        array_push(_list, ["sta_zp",  _B_HI, _id]);
        array_push(_list, ["label",   "math_mul16_bpos"]);
        // unsigned product: R = 0, 16 iterations of (shift A into carry;
        // if set add B to R) — standard shift-add with A as multiplier.
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        array_push(_list, ["ldx_imm", 16, _id]);
        array_push(_list, ["label", "math_mul16_lp"]);
        // shift A right, low bit -> carry
        array_push(_list, ["lsr_zp",  _A_HI, _id]);
        array_push(_list, ["ror_zp",  _A_LO, _id]);
        array_push(_list, ["bcc",     "math_mul16_no", _id]);
        // R += B
        array_push(_list, ["clc",     0, _id]);
        array_push(_list, ["lda_zp",  _R_LO, _id]);
        array_push(_list, ["adc_zp",  _B_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_zp",  _R_HI, _id]);
        array_push(_list, ["adc_zp",  _B_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        array_push(_list, ["label", "math_mul16_no"]);
        // B <<= 1
        array_push(_list, ["asl_zp",  _B_LO, _id]);
        array_push(_list, ["rol_zp",  _B_HI, _id]);
        array_push(_list, ["dex",     0, _id]);
        array_push(_list, ["bne",     "math_mul16_lp", _id]);
        // apply sign: if parity odd, negate R
        array_push(_list, ["lda_zp",  _SGN, _id]);
        array_push(_list, ["and_imm", 0x01, _id]);
        array_push(_list, ["beq",     "math_mul16_done", _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _R_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _R_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        array_push(_list, ["label", "math_mul16_done"]);
        array_push(_list, ["rts", 0, _id]);

        // ────────────────────────────────────────────────────────────
        // math_div16 — signed 16/16 -> 16 quotient, truncate toward zero.
        // In:  $F2/$F3 = dividend A,  $F4/$F5 = divisor B
        // Out: $F6/$F7 = quotient.  Divide-by-zero -> quotient 0.
        // Method: |A|/|B| unsigned restoring division (16-bit), remainder
        //   in $F0/$F1, quotient shifted into $F6/$F7; sign of quotient is
        //   parity of operand signs. Clobbers A,X,Y,$F0,$F1.
        // ────────────────────────────────────────────────────────────
        array_push(_list, ["label", "math_div16"]);
        // divide-by-zero guard: if B == 0 -> R = 0, return
        array_push(_list, ["lda_zp",  _B_LO, _id]);
        array_push(_list, ["ora_zp",  _B_HI, _id]);
        array_push(_list, ["bne",     "math_div16_ok", _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", "math_div16_ok"]);
        // sign parity = 0
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  _SGN, _id]);
        // |A|
        array_push(_list, ["lda_zp",  _A_HI, _id]);
        array_push(_list, ["and_imm", 0x80, _id]);
        array_push(_list, ["beq",     "math_div16_apos", _id]);
        array_push(_list, ["inc_zp",  _SGN, _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_LO, _id]);
        array_push(_list, ["sta_zp",  _A_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _A_HI, _id]);
        array_push(_list, ["sta_zp",  _A_HI, _id]);
        array_push(_list, ["label",   "math_div16_apos"]);
        // |B|
        array_push(_list, ["lda_zp",  _B_HI, _id]);
        array_push(_list, ["and_imm", 0x80, _id]);
        array_push(_list, ["beq",     "math_div16_bpos", _id]);
        array_push(_list, ["inc_zp",  _SGN, _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _B_LO, _id]);
        array_push(_list, ["sta_zp",  _B_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _B_HI, _id]);
        array_push(_list, ["sta_zp",  _B_HI, _id]);
        array_push(_list, ["label",   "math_div16_bpos"]);
        // remainder $F0/$F1 = 0; quotient built in $F6/$F7 (reuse A slot as
        // the shifting dividend so we don't need a 5th ZP pair)
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF1, _id]);
        array_push(_list, ["ldx_imm", 16, _id]);
        array_push(_list, ["label", "math_div16_lp"]);
        // shift dividend (A) left into remainder
        array_push(_list, ["asl_zp",  _A_LO, _id]);
        array_push(_list, ["rol_zp",  _A_HI, _id]);
        array_push(_list, ["rol_zp",  0xF0, _id]);
        array_push(_list, ["rol_zp",  0xF1, _id]);
        // if remainder >= divisor, subtract and set quotient bit (via C)
        array_push(_list, ["lda_zp",  0xF1, _id]);
        array_push(_list, ["cmp_zp",  _B_HI, _id]);
        array_push(_list, ["bcc",     "math_div16_skip", _id]);
        array_push(_list, ["bne",     "math_div16_sub", _id]);
        // hi equal — compare lo
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["cmp_zp",  _B_LO, _id]);
        array_push(_list, ["bcc",     "math_div16_skip", _id]);
        array_push(_list, ["label", "math_div16_sub"]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["sbc_zp",  _B_LO, _id]);
        array_push(_list, ["sta_zp",  0xF0, _id]);
        array_push(_list, ["lda_zp",  0xF1, _id]);
        array_push(_list, ["sbc_zp",  _B_HI, _id]);
        array_push(_list, ["sta_zp",  0xF1, _id]);
        array_push(_list, ["inc_zp",  _A_LO, _id]); // set low quotient bit
        array_push(_list, ["label", "math_div16_skip"]);
        array_push(_list, ["dex",     0, _id]);
        array_push(_list, ["bne",     "math_div16_lp", _id]);
        // quotient now sits in $F2/$F3 (A slot); move to $F6/$F7
        array_push(_list, ["lda_zp",  _A_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_zp",  _A_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        // apply sign
        array_push(_list, ["lda_zp",  _SGN, _id]);
        array_push(_list, ["and_imm", 0x01, _id]);
        array_push(_list, ["beq",     "math_div16_done", _id]);
        array_push(_list, ["sec",     0, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _R_LO, _id]);
        array_push(_list, ["sta_zp",  _R_LO, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_zp",  _R_HI, _id]);
        array_push(_list, ["sta_zp",  _R_HI, _id]);
        array_push(_list, ["label", "math_div16_done"]);
        array_push(_list, ["rts", 0, _id]);

        array_push(_list, ["label", "math_helpers_skip"]);
    }
} break;
				
// --------------------------------------------------------
// MACRO_CLR_SCREEN
// Fills 1000 bytes of screen RAM with FILL. Two loops, mirroring
// the MACRO_MAP_SWITCH clearer: pages 0-2 fill in full via a
// wrapping bne loop; the fourth page stops at base+$3E8 (232
// bytes) so the fill never touches the sprite pointer table at
// base+$3F8-$3FF. Covers base..base+$3E7 (exactly 1000 bytes).
// Per-node label prefix keeps multiple CLR nodes from colliding.
// --------------------------------------------------------
case "MACRO_CLR_SCREEN": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _scr_base = (array_length(_i0) > 1 && is_real(_i0[1])) ? real(_i0[1]) : 0x0400;
    var _fill     = (array_length(_i0) > 2 && is_real(_i0[2])) ? (real(_i0[2]) & 0xFF) : 0;

    var _clr_pfx  = "clrscr_" + string(real(_id)) + "_";
    var _lbl_p012 = _clr_pfx + "p012";

    array_push(_list, ["lda_imm", _fill,                        _id]);
    array_push(_list, ["ldx_imm", 0x00,                         _id]);
    array_push(_list, ["label",   _lbl_p012                        ]);
    array_push(_list, ["sta_abx", (_scr_base + 0x000) & 0xFFFF,  _id]);
    array_push(_list, ["sta_abx", (_scr_base + 0x100) & 0xFFFF,  _id]);
    array_push(_list, ["sta_abx", (_scr_base + 0x200) & 0xFFFF,  _id]);
    array_push(_list, ["sta_abx", (_scr_base + 0x2F8) & 0xFFFF,  _id]);
    array_push(_list, ["inx",     0,                            _id]);
    array_push(_list, ["bne",     _lbl_p012,                     _id]);
} break;

// --------------------------------------------------------
// MACRO_PLACE_CHAR
// Writes one screencode (and optionally colour) at row/col.
// Address maths is shift-add: row*40 = (row<<5) + (row<<3).
// Uses 4 consecutive ZP bytes from zp_base: base+0/1 = screen ptr,
// base+2/3 = colour ptr (also used as scratch for the row*8 stash).
// --------------------------------------------------------
case "MACRO_PLACE_CHAR": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _col_lit   = (array_length(_i0) > 1  && is_real(_i0[1]))  ? real(_i0[1])  : 0;
    var _col_vmode = (array_length(_i0) > 2  && is_real(_i0[2]))  ? real(_i0[2])  : 0;
    var _col_var   = (array_length(_i0) > 3)  ? string(_i0[3])  : "";
    var _row_lit   = (array_length(_i0) > 4  && is_real(_i0[4]))  ? real(_i0[4])  : 0;
    var _row_vmode = (array_length(_i0) > 5  && is_real(_i0[5]))  ? real(_i0[5])  : 0;
    var _row_var   = (array_length(_i0) > 6)  ? string(_i0[6])  : "";
    var _chr_src   = (array_length(_i0) > 7  && is_real(_i0[7]))  ? real(_i0[7])  : 0;
    var _chr_lit   = (array_length(_i0) > 8  && is_real(_i0[8]))  ? real(_i0[8])  : 32;
    var _chr_var   = (array_length(_i0) > 9)  ? string(_i0[9])  : "";
    var _chr_asset = (array_length(_i0) > 10) ? string(_i0[10]) : "";
    var _idx_vmode = (array_length(_i0) > 11 && is_real(_i0[11])) ? real(_i0[11]) : 0;
    var _idx_lit   = (array_length(_i0) > 12 && is_real(_i0[12])) ? real(_i0[12]) : 0;
    var _idx_var   = (array_length(_i0) > 13) ? string(_i0[13]) : "";
    var _set_col   = (array_length(_i0) > 14 && is_real(_i0[14])) ? real(_i0[14]) : 1;
    var _col_val   = (array_length(_i0) > 15 && is_real(_i0[15])) ? clamp(real(_i0[15]), 0, 15) : 1;
    var _scr_base  = (array_length(_i0) > 16 && is_real(_i0[16])) ? real(_i0[16]) : 0x0400;
    var _zp        = (array_length(_i0) > 17 && is_real(_i0[17])) ? real(_i0[17]) : 0xFB;

    var _zp_sl = _zp;
    var _zp_sh = _zp + 1;
    var _zp_cl = _zp + 2;
    var _zp_ch = _zp + 3;

    var _col_addr = scr_resolve_var_addr(_col_var);
    var _row_addr = scr_resolve_var_addr(_row_var);
    var _chr_addr = scr_resolve_var_addr(_chr_var);
    var _idx_addr = scr_resolve_var_addr(_idx_var);

    // ---- offset = row * 40 ----
    if (_row_vmode == 1 && _row_addr != 0) {
        array_push(_list, ["lda_abs", _row_addr, _id]);
    } else {
        array_push(_list, ["lda_imm", _row_lit & 0xFF, _id]);
    }
    array_push(_list, ["sta_zp",  _zp_sl, _id]);
    array_push(_list, ["lda_imm", 0,      _id]);
    array_push(_list, ["sta_zp",  _zp_sh, _id]);

    // x8
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);

    // stash row*8 in the colour-ptr slots (reused as scratch)
    array_push(_list, ["lda_zp", _zp_sl, _id]);
    array_push(_list, ["sta_zp", _zp_cl, _id]);
    array_push(_list, ["lda_zp", _zp_sh, _id]);
    array_push(_list, ["sta_zp", _zp_ch, _id]);

    // x32
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);

    // row*32 + row*8 = row*40
    array_push(_list, ["clc",    0,      _id]);
    array_push(_list, ["lda_zp", _zp_sl, _id]);
    array_push(_list, ["adc_zp", _zp_cl, _id]);
    array_push(_list, ["sta_zp", _zp_sl, _id]);
    array_push(_list, ["lda_zp", _zp_sh, _id]);
    array_push(_list, ["adc_zp", _zp_ch, _id]);
    array_push(_list, ["sta_zp", _zp_sh, _id]);

    // + col
    array_push(_list, ["clc",    0,      _id]);
    array_push(_list, ["lda_zp", _zp_sl, _id]);
    if (_col_vmode == 1 && _col_addr != 0) {
        array_push(_list, ["adc_abs", _col_addr, _id]);
    } else {
        array_push(_list, ["adc_imm", _col_lit & 0xFF, _id]);
    }
    array_push(_list, ["sta_zp",  _zp_sl, _id]);
    array_push(_list, ["lda_zp",  _zp_sh, _id]);
    array_push(_list, ["adc_imm", 0,      _id]);
    array_push(_list, ["sta_zp",  _zp_sh, _id]);

    // colour ptr = offset + $D800 (built BEFORE scr_base folds in)
    if (_set_col == 1) {
        array_push(_list, ["clc",     0,      _id]);
        array_push(_list, ["lda_zp",  _zp_sl, _id]);
        array_push(_list, ["adc_imm", 0x00,   _id]);
        array_push(_list, ["sta_zp",  _zp_cl, _id]);
        array_push(_list, ["lda_zp",  _zp_sh, _id]);
        array_push(_list, ["adc_imm", 0xD8,   _id]);
        array_push(_list, ["sta_zp",  _zp_ch, _id]);
    }

    // screen ptr = offset + scr_base
    array_push(_list, ["clc",     0,                          _id]);
    array_push(_list, ["lda_zp",  _zp_sl,                     _id]);
    array_push(_list, ["adc_imm", _scr_base & 0xFF,           _id]);
    array_push(_list, ["sta_zp",  _zp_sl,                     _id]);
    array_push(_list, ["lda_zp",  _zp_sh,                     _id]);
    array_push(_list, ["adc_imm", (_scr_base >> 8) & 0xFF,    _id]);
    array_push(_list, ["sta_zp",  _zp_sh,                     _id]);

    // ---- fetch the character ----
    if (_chr_src == 2 && _chr_asset != "") {
        var _a_addr = -1;
        if (instance_exists(obj_asset_manager)) {
            var _am_pc = obj_asset_manager;
            for (var _pci = 0; _pci < ds_list_size(_am_pc.asset_list); _pci++) {
                var _pa = ds_list_find_value(_am_pc.asset_list, _pci);
                if (_pa.type == "BYTE_DATA" && _pa.name == _chr_asset) {
                    _a_addr = _pa.address;
                    break;
                }
            }
        }
        if (_a_addr < 0) {
            show_debug_message("MACRO_PLACE_CHAR WARNING: asset '" + _chr_asset + "' not found.");
            array_push(_list, ["lda_imm", _chr_lit & 0xFF, _id]);
        } else {
            if (_idx_vmode == 1 && _idx_addr != 0) {
                array_push(_list, ["ldx_abs", _idx_addr, _id]);
            } else {
                array_push(_list, ["ldx_imm", _idx_lit & 0xFF, _id]);
            }
            array_push(_list, ["lda_abx", _a_addr, _id]);
        }
    } else if (_chr_src == 1 && _chr_addr != 0) {
        array_push(_list, ["lda_abs", _chr_addr, _id]);
    } else {
        array_push(_list, ["lda_imm", _chr_lit & 0xFF, _id]);
    }

    // ---- store ----
    array_push(_list, ["ldy_imm", 0,      _id]);
    array_push(_list, ["sta_izy", _zp_sl, _id]);

    if (_set_col == 1) {
        array_push(_list, ["lda_imm", _col_val, _id]);
        array_push(_list, ["sta_izy", _zp_cl,   _id]);
    }
} break;

// --------------------------------------------------------
// MACRO_RANDOM
// SID voice-3 noise RNG. Optional one-time oscillator setup,
// reads $D41B, optional branchless clamp to [MIN,MAX], result
// left in A and/or stored to a named VAR.
// --------------------------------------------------------
case "MACRO_RANDOM": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _init_osc = 1;
    if (array_length(_i0) > 1 && is_real(_i0[1])) { _init_osc = real(_i0[1]); }

    var _freq = 0xFFFF;
    if (array_length(_i0) > 2 && is_real(_i0[2])) { _freq = real(_i0[2]) & 0xFFFF; }

    var _clamp_on = 0;
    if (array_length(_i0) > 3 && is_real(_i0[3])) { _clamp_on = real(_i0[3]); }

    var _clamp_min = 0;
    if (array_length(_i0) > 4 && is_real(_i0[4])) { _clamp_min = real(_i0[4]) & 0xFF; }

    var _clamp_max = 255;
    if (array_length(_i0) > 5 && is_real(_i0[5])) { _clamp_max = real(_i0[5]) & 0xFF; }

    var _dst_mode = 0;
    if (array_length(_i0) > 6 && is_real(_i0[6])) { _dst_mode = real(_i0[6]); }

    var _dst_var = "";
    if (array_length(_i0) > 7) { _dst_var = string(_i0[7]); }

    var _zp = 0xFB;
    if (array_length(_i0) > 8 && is_real(_i0[8])) { _zp = real(_i0[8]) & 0xFF; }

    var _zp_v = _zp;
    var _zp_m = _zp + 1;

    var _dst_addr = 0;
    if (_dst_mode == 1) {
        _dst_addr = scr_resolve_var_addr(_dst_var);
        if (_dst_addr == 0) {
            show_debug_message("MACRO_RANDOM WARNING: dest var '" + _dst_var + "' not resolved.");
        }
    }

    // guard swapped range
    if (_clamp_min > _clamp_max) {
        var _swap  = _clamp_min;
        _clamp_min = _clamp_max;
        _clamp_max = _swap;
    }

    // ---- one-time voice-3 noise oscillator setup ----
    if (_init_osc == 1) {
        array_push(_list, ["lda_imm", _freq & 0xFF,        _id]);
        array_push(_list, ["sta_abs", 0xD40E,              _id]);
        array_push(_list, ["lda_imm", (_freq >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_abs", 0xD40F,              _id]);
        array_push(_list, ["lda_imm", 0x80,                _id]);
        array_push(_list, ["sta_abs", 0xD412,              _id]);
    }

    // ---- read random byte ----
    array_push(_list, ["lda_abs", 0xD41B, _id]);

    // ---- optional branchless clamp to [min,max] ----
    if (_clamp_on == 1) {

        // low clamp: A = max(A, MIN)
        array_push(_list, ["sta_zp",  _zp_v,      _id]);
        array_push(_list, ["cmp_imm", _clamp_min, _id]);   // C=1 if A>=MIN
        array_push(_list, ["lda_imm", 0x00,       _id]);
        array_push(_list, ["sbc_imm", 0x00,       _id]);   // $FF if A<MIN else $00 (sub mask)
        array_push(_list, ["sta_zp",  _zp_m,      _id]);
        array_push(_list, ["eor_imm", 0xFF,       _id]);   // keep mask
        array_push(_list, ["and_zp",  _zp_v,      _id]);   // value & keep
        array_push(_list, ["sta_zp",  _zp_v,      _id]);
        array_push(_list, ["lda_zp",  _zp_m,      _id]);   // sub mask
        array_push(_list, ["and_imm", _clamp_min, _id]);   // MIN & sub
        array_push(_list, ["ora_zp",  _zp_v,      _id]);
        array_push(_list, ["sta_zp",  _zp_v,      _id]);   // = max(value,MIN)

        // high clamp: A = min(value, MAX)  (skip when MAX==255)
        if (_clamp_max < 255) {
            array_push(_list, ["lda_zp",  _zp_v,                  _id]);
            array_push(_list, ["cmp_imm", (_clamp_max + 1) & 0xFF, _id]); // C=1 if value>MAX
            array_push(_list, ["lda_imm", 0x00,                  _id]);
            array_push(_list, ["sbc_imm", 0x00,                  _id]);   // keep mask: $FF if value<=MAX
            array_push(_list, ["sta_zp",  _zp_m,                 _id]);
            array_push(_list, ["and_zp",  _zp_v,                 _id]);   // value & keep
            array_push(_list, ["sta_zp",  _zp_v,                 _id]);
            array_push(_list, ["lda_zp",  _zp_m,                 _id]);
            array_push(_list, ["eor_imm", 0xFF,                  _id]);   // ~keep
            array_push(_list, ["and_imm", _clamp_max,            _id]);   // MAX & ~keep
            array_push(_list, ["ora_zp",  _zp_v,                 _id]);
            array_push(_list, ["sta_zp",  _zp_v,                 _id]);   // = min(value,MAX)
        }

        array_push(_list, ["lda_zp", _zp_v, _id]);   // final value -> A
    }

    // ---- store to VAR if requested ----
    if (_dst_mode == 1 && _dst_addr != 0) {
        array_push(_list, ["sta_abs", _dst_addr, _id]);
    }
} break;


	
// --------------------------------------------------------
// MACRO_SID_SOUND
// Plays a note on a chosen SID voice. WAVE ($D404) carries the
// waveform bits AND the gate bit, so it's written LAST to gate on
// after freq/ADSR/PW are set.
//   LIT voice -> fixed sta_abs to that voice's registers.
//   VAR voice -> X = voice*7 (v*8-v), sta_abs,X off $D400 base.
//   NOTE VAR  -> 16-bit freq var (lo/hi consecutive).
// --------------------------------------------------------
case "MACRO_SID_SOUND": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _voice_mode = (array_length(_i0) > 1 && is_real(_i0[1]))  ? real(_i0[1]) : 0;
    var _voice_lit  = (array_length(_i0) > 2 && is_real(_i0[2]))  ? clamp(real(_i0[2]), 0, 2) : 0;
    var _voice_var  = (array_length(_i0) > 3)  ? string(_i0[3])  : "";
    var _note_mode  = (array_length(_i0) > 4 && is_real(_i0[4]))  ? real(_i0[4]) : 0;
    var _note_lit   = (array_length(_i0) > 5 && is_real(_i0[5]))  ? real(_i0[5]) & 0xFFFF : 0;
    var _note_var   = (array_length(_i0) > 6)  ? string(_i0[6])  : "";
    var _wave_mode  = (array_length(_i0) > 7 && is_real(_i0[7]))  ? real(_i0[7]) : 0;
    var _wave_lit   = (array_length(_i0) > 8 && is_real(_i0[8]))  ? real(_i0[8]) & 0xFF : 0;
    var _wave_var   = (array_length(_i0) > 9)  ? string(_i0[9])  : "";
    var _ad_mode    = (array_length(_i0) > 10 && is_real(_i0[10])) ? real(_i0[10]) : 0;
    var _ad_lit     = (array_length(_i0) > 11 && is_real(_i0[11])) ? real(_i0[11]) & 0xFF : 0;
    var _ad_var     = (array_length(_i0) > 12) ? string(_i0[12]) : "";
    var _sr_mode    = (array_length(_i0) > 13 && is_real(_i0[13])) ? real(_i0[13]) : 0;
    var _sr_lit     = (array_length(_i0) > 14 && is_real(_i0[14])) ? real(_i0[14]) & 0xFF : 0;
    var _sr_var     = (array_length(_i0) > 15) ? string(_i0[15]) : "";
    var _pulse_on   = (array_length(_i0) > 16 && is_real(_i0[16])) ? real(_i0[16]) : 0;
    var _pw_mode    = (array_length(_i0) > 17 && is_real(_i0[17])) ? real(_i0[17]) : 0;
    var _pw_lit     = (array_length(_i0) > 18 && is_real(_i0[18])) ? real(_i0[18]) & 0x0FFF : 0;
    var _pw_var     = (array_length(_i0) > 19) ? string(_i0[19]) : "";
    var _zp         = (array_length(_i0) > 20 && is_real(_i0[20])) ? real(_i0[20]) & 0xFF : 0xFC;
    var _note_ast   = (array_length(_i0) > 21) ? string(_i0[21]) : "";
    var _off_mode   = (array_length(_i0) > 22 && is_real(_i0[22])) ? real(_i0[22]) : 0;
    var _off_lit    = (array_length(_i0) > 23 && is_real(_i0[23])) ? real(_i0[23]) & 0xFF : 0;
    var _off_var    = (array_length(_i0) > 24) ? string(_i0[24]) : "";
    var _wave_ast   = (array_length(_i0) > 25) ? string(_i0[25]) : "";
    var _woff_mode  = (array_length(_i0) > 26 && is_real(_i0[26])) ? real(_i0[26]) : 0;
    var _woff_lit   = (array_length(_i0) > 27 && is_real(_i0[27])) ? real(_i0[27]) & 0xFF : 0;
    var _woff_var   = (array_length(_i0) > 28) ? string(_i0[28]) : "";

    var _voice_addr = (_voice_mode == 1) ? scr_resolve_var_addr(_voice_var) : 0;
    var _note_addr  = (_note_mode  == 1) ? scr_resolve_var_addr(_note_var)  : 0;
    var _wave_addr  = (_wave_mode  == 1) ? scr_resolve_var_addr(_wave_var)  : 0;
    var _ad_addr    = (_ad_mode    == 1) ? scr_resolve_var_addr(_ad_var)    : 0;
    var _sr_addr    = (_sr_mode    == 1) ? scr_resolve_var_addr(_sr_var)    : 0;
    var _pw_addr    = (_pw_mode    == 1) ? scr_resolve_var_addr(_pw_var)    : 0;

    // Store op + base depend on voice mode.
    var _use_x = (_voice_mode == 1);
    var _base  = _use_x ? 0xD400 : (0xD400 + _voice_lit * 7);
    var _stop  = _use_x ? "sta_abx" : "sta_abs";

    // ── ASSET note mode: compile the TEXT_DATA into three tables ──
    // Y holds the note index throughout, so it never collides with the
    // VAR-voice X offset. Tables are jumped over and tagged _id so Pass 1.5
    // sizes them onto this node.
    var _note_pfx  = "sidnt_" + string(real(_id)) + "_";
    var _lbl_nlo   = _note_pfx + "lo";
    var _lbl_nhi   = _note_pfx + "hi";
    var _lbl_ngt   = _note_pfx + "gt";
    var _lbl_nskip = _note_pfx + "skip";
    var _lbl_rest  = _note_pfx + "rest";
    var _notes     = [];
    var _use_asset = false;

    if (_note_mode == 2 && _note_ast != "") {
        var _ntxt = "";
        var _nfound = false;
        if (instance_exists(obj_asset_manager)) {
            var _am_n = obj_asset_manager;
            for (var _ni = 0; _ni < ds_list_size(_am_n.asset_list); _ni++) {
                var _a_n = ds_list_find_value(_am_n.asset_list, _ni);
                if (_a_n.type == "TEXT_DATA" && _a_n.name == _note_ast) {
                    if (variable_struct_exists(_a_n.meta, "text")) {
                        _ntxt = string(_a_n.meta.text);
                    }
                    _nfound = true;
                    break;
                }
            }
        }
        if (!_nfound) {
            show_debug_message("MACRO_SID_SOUND: note asset '" + _note_ast + "' not found — falling back to LIT freq.");
        } else {
            _notes = scr_sid_notes_parse(_ntxt);
            if (array_length(_notes) == 0) {
                show_debug_message("MACRO_SID_SOUND: note asset '" + _note_ast + "' parsed to zero notes — falling back to LIT freq.");
            } else {
                _use_asset = true;
            }
        }
    }

    if (_use_asset) {
        // A byte index can only reach 256 entries; a word index reaches the
        // whole table. Clamp to whichever the chosen index actually addresses
        // rather than emitting bytes nothing can read.
        var _ncount = array_length(_notes);
        var _nmax   = 256;
        if (_off_mode == 1 && _off_var != "") {
            var _pre_meta = scr_nloc_find_meta(_off_var);
            if (_pre_meta != undefined && variable_struct_exists(_pre_meta, "size")) {
                if (real(_pre_meta.size) >= 2) {
                    _nmax = 65536;
                }
            }
        }
        if (_ncount > _nmax) {
            show_debug_message("MACRO_SID_SOUND: note asset '" + _note_ast + "' has "
                + string(_ncount) + " notes but the index reaches only " + string(_nmax)
                + "; the rest are dropped. Use a word var for longer lists.");
            _ncount = _nmax;
        }
        array_push(_list, ["jmp_abs", _lbl_nskip, _id]);
        array_push(_list, ["label",   _lbl_nlo       ]);
        for (var _ti = 0; _ti < _ncount; _ti++) {
            array_push(_list, ["byte", _notes[_ti].freq & 0xFF, _id]);
        }
        array_push(_list, ["label",   _lbl_nhi       ]);
        for (var _ti = 0; _ti < _ncount; _ti++) {
            array_push(_list, ["byte", (_notes[_ti].freq >> 8) & 0xFF, _id]);
        }
        array_push(_list, ["label",   _lbl_ngt       ]);
        for (var _ti = 0; _ti < _ncount; _ti++) {
            array_push(_list, ["byte", _notes[_ti].gate & 0xFF, _id]);
        }
        array_push(_list, ["label",   _lbl_nskip     ]);

        // ── Index into the tables ──
        // BYTE var (or literal): Y holds the index outright and the reads are
        // plain lda TABLE,Y. Cheapest path, capped at 256 notes.
        //
        // WORD var: Y can't carry a 16-bit index, so build three ZP pointers
        // (table_base + index) and read via lda (ptr),Y with Y = 0. Costs six
        // ZP bytes and ~36 bytes of setup, and lifts the ceiling to the whole
        // table. The var's declared size decides — no extra node field.
        var _off_addr = 0;
        var _off_word = false;
        if (_off_mode == 1 && _off_var != "") {
            _off_addr = scr_resolve_var_addr(_off_var);
            if (_off_addr != 0) {
                var _off_meta = scr_nloc_find_meta(_off_var);
                if (_off_meta != undefined && variable_struct_exists(_off_meta, "size")) {
                    if (real(_off_meta.size) >= 2) {
                        _off_word = true;
                    }
                }
            }
        }

        // ZP pointer trio for the word path. Derived from the node's ZP slot so
        // the user can move them off anything else living down there.
        var _nzp_lo = _zp;
        var _nzp_hi = _zp + 2;
        var _nzp_gt = _zp + 4;
        if (_off_word && _zp > 0xFA) {
            show_debug_message("MACRO_SID_SOUND: ZP $" + string_upper(decimal_to_hex(_zp))
                + " leaves no room for the 6-byte word-index pointers; using $F2.");
            _nzp_lo = 0xF2;
            _nzp_hi = 0xF4;
            _nzp_gt = 0xF6;
        }

        if (_off_word) {
            // ptr = table + index, one 16-bit add per table. lda_lab_lo/hi
            // load a label's low/high byte as an immediate — same mechanism
            // MACRO_IRQ uses to poke a handler address into a vector.
            array_push(_list, ["clc",        0,             _id]);
            array_push(_list, ["lda_lab_lo", _lbl_nlo,      _id]);
            array_push(_list, ["adc_abs",    _off_addr,     _id]);
            array_push(_list, ["sta_zp",     _nzp_lo,       _id]);
            array_push(_list, ["lda_lab_hi", _lbl_nlo,      _id]);
            array_push(_list, ["adc_abs",    _off_addr + 1, _id]);
            array_push(_list, ["sta_zp",     _nzp_lo + 1,   _id]);

            array_push(_list, ["clc",        0,             _id]);
            array_push(_list, ["lda_lab_lo", _lbl_nhi,      _id]);
            array_push(_list, ["adc_abs",    _off_addr,     _id]);
            array_push(_list, ["sta_zp",     _nzp_hi,       _id]);
            array_push(_list, ["lda_lab_hi", _lbl_nhi,      _id]);
            array_push(_list, ["adc_abs",    _off_addr + 1, _id]);
            array_push(_list, ["sta_zp",     _nzp_hi + 1,   _id]);

            array_push(_list, ["clc",        0,             _id]);
            array_push(_list, ["lda_lab_lo", _lbl_ngt,      _id]);
            array_push(_list, ["adc_abs",    _off_addr,     _id]);
            array_push(_list, ["sta_zp",     _nzp_gt,       _id]);
            array_push(_list, ["lda_lab_hi", _lbl_ngt,      _id]);
            array_push(_list, ["adc_abs",    _off_addr + 1, _id]);
            array_push(_list, ["sta_zp",     _nzp_gt + 1,   _id]);

            array_push(_list, ["ldy_imm", 0, _id]);
        } else if (_off_addr != 0) {
            array_push(_list, ["ldy_abs", _off_addr, _id]);
        } else {
            if (_off_mode == 1) {
                show_debug_message("MACRO_SID_SOUND: offset var '" + _off_var + "' unresolved; using index " + string(_off_lit) + ".");
            }
            array_push(_list, ["ldy_imm", _off_lit & 0xFF, _id]);
        }
    }

    // --- VAR voice: X = voice * 7  (v*8 - v) ---
    if (_use_x) {
        if (_voice_addr != 0) {
            array_push(_list, ["lda_abs", _voice_addr, _id]);
        } else {
            show_debug_message("MACRO_SID_SOUND WARNING: voice var '" + _voice_var + "' unresolved; using voice 1.");
            array_push(_list, ["lda_imm", 0x00, _id]);
        }
        array_push(_list, ["sta_zp", _zp, _id]);
        array_push(_list, ["asl_a",  0,   _id]);
        array_push(_list, ["asl_a",  0,   _id]);
        array_push(_list, ["asl_a",  0,   _id]);
        array_push(_list, ["sec",    0,   _id]);
        array_push(_list, ["sbc_zp", _zp, _id]);
        array_push(_list, ["tax",    0,   _id]);
    }

    // --- AD (off 5) ---
    if (_ad_mode == 1 && _ad_addr != 0) {
        array_push(_list, ["lda_abs", _ad_addr, _id]);
    } else {
        array_push(_list, ["lda_imm", _ad_lit,  _id]);
    }
    array_push(_list, [_stop, _base + 5, _id]);

    // --- SR (off 6) ---
    if (_sr_mode == 1 && _sr_addr != 0) {
        array_push(_list, ["lda_abs", _sr_addr, _id]);
    } else {
        array_push(_list, ["lda_imm", _sr_lit,  _id]);
    }
    array_push(_list, [_stop, _base + 6, _id]);

// --- PULSE WIDTH (off 2,3) — only if enabled ---
    if (_pulse_on == 1) {
        if (_pw_mode == 1 && _pw_addr != 0) {
            array_push(_list, ["lda_abs", _pw_addr,     _id]);
            array_push(_list, [_stop, _base + 2,        _id]);
            array_push(_list, ["lda_abs", _pw_addr + 1, _id]);
            array_push(_list, [_stop, _base + 3,        _id]);
        } else {
            array_push(_list, ["lda_imm", _pw_lit & 0xFF,        _id]);
            array_push(_list, [_stop, _base + 2,                 _id]);
            array_push(_list, ["lda_imm", (_pw_lit >> 8) & 0x0F, _id]);
            array_push(_list, [_stop, _base + 3,                 _id]);
        }
    }

    // ── WAVE ASSET mode: read the control byte from a BYTE_DATA list ──
    // No table emission — the asset is already injected and addressed, so this
    // is a straight indexed read. Its index is independent of the note index,
    // so one pointer can walk a melody while another selects an instrument.
    //   $00 -> written literally: waveform bits clear, gate clear = note off.
    //   $FF -> skip the write entirely: the voice keeps its current control
    //          byte. Doubles as a sentinel for the user's own table walking.
    var _wave_ast_base = 0;
    var _use_wave_ast  = false;
    var _woff_addr     = 0;
    var _woff_word     = false;

    if (_wave_mode == 2 && _wave_ast != "" && _wave_ast != "[clear]") {
        if (instance_exists(obj_asset_manager)) {
            var _am_w = obj_asset_manager;
            for (var _wi = 0; _wi < ds_list_size(_am_w.asset_list); _wi++) {
                var _a_w = ds_list_find_value(_am_w.asset_list, _wi);
                if (_a_w.type == "BYTE_DATA" && _a_w.name == _wave_ast) {
                    _wave_ast_base = _a_w.address;
                    break;
                }
            }
        }
        if (_wave_ast_base == 0) {
            show_debug_message("MACRO_SID_SOUND: wave asset '" + _wave_ast + "' not found — falling back to LIT wave.");
        } else {
            _use_wave_ast = true;
            if (_woff_mode == 1 && _woff_var != "") {
                _woff_addr = scr_resolve_var_addr(_woff_var);
                if (_woff_addr != 0) {
                    var _woff_meta = scr_nloc_find_meta(_woff_var);
                    if (_woff_meta != undefined && variable_struct_exists(_woff_meta, "size")) {
                        if (real(_woff_meta.size) >= 2) {
                            _woff_word = true;
                        }
                    }
                }
            }
        }
    }

    // Word wave index needs its own ZP pointer pair, clear of the note trio.
    var _wzp = _zp + 6;
    if (_use_wave_ast && _woff_word && _wzp > 0xFE) {
        show_debug_message("MACRO_SID_SOUND: ZP $" + string_upper(decimal_to_hex(_zp))
            + " leaves no room for the word wave pointer; using $F8.");
        _wzp = 0xF8;
    }

    // --- REST TEST (ASSET mode) ---
    // The gate byte is read BEFORE the frequency so one branch clears both
    // the freq write and the WAVE write. A rest therefore leaves the voice
    // completely untouched — it keeps ringing at its current pitch through
    // the envelope's sustain. Writing the table's $0000 freq would drag a
    // sustaining note down to silence, which is a mute, not a rest.
    // AD/SR/PW above are still written; they only take effect on the next
    // gate-on, so setting them during a rest is harmless and lets a rest
    // double as an envelope change for the note that follows.
    if (_use_asset) {
        if (_off_word) {
            array_push(_list, ["lda_izy", _nzp_gt, _id]);
        } else {
            array_push(_list, ["lda_aby", _lbl_ngt, _id]);
        }
        array_push(_list, ["beq", _lbl_rest, _id]);
    }

    // --- FREQUENCY (off 0,1) ---
    if (_use_asset) {
        if (_off_word) {
            // Y is 0; the ZP pointers already carry the index.
            array_push(_list, ["lda_izy", _nzp_lo, _id]);
            array_push(_list, [_stop, _base + 0,   _id]);
            array_push(_list, ["lda_izy", _nzp_hi, _id]);
            array_push(_list, [_stop, _base + 1,   _id]);
        } else {
            // Y still holds the note index. lda_aby against the emitted tables.
            array_push(_list, ["lda_aby", _lbl_nlo, _id]);
            array_push(_list, [_stop, _base + 0,    _id]);
            array_push(_list, ["lda_aby", _lbl_nhi, _id]);
            array_push(_list, [_stop, _base + 1,    _id]);
        }
    } else if (_note_mode == 1 && _note_addr != 0) {
        array_push(_list, ["lda_abs", _note_addr,     _id]);
        array_push(_list, [_stop, _base + 0,          _id]);
        array_push(_list, ["lda_abs", _note_addr + 1, _id]);
        array_push(_list, [_stop, _base + 1,          _id]);
    } else {
        array_push(_list, ["lda_imm", _note_lit & 0xFF,        _id]);
        array_push(_list, [_stop, _base + 0,                   _id]);
        array_push(_list, ["lda_imm", (_note_lit >> 8) & 0xFF, _id]);
        array_push(_list, [_stop, _base + 1,                   _id]);
    }

    // --- WAVE / CONTROL (off 4) — LAST, gates the note on ---
    if (_use_wave_ast) {
        var _lbl_wskip = _note_pfx + "wskip";
        if (_woff_word) {
            // ptr = asset_base + index, then lda (ptr),Y with Y = 0. Y is
            // reloaded here regardless — the note reads above are finished
            // with it, so the two lists never fight over the register.
            array_push(_list, ["clc",     0,                          _id]);
            array_push(_list, ["lda_imm", _wave_ast_base & 0xFF,      _id]);
            array_push(_list, ["adc_abs", _woff_addr,                 _id]);
            array_push(_list, ["sta_zp",  _wzp,                       _id]);
            array_push(_list, ["lda_imm", (_wave_ast_base >> 8) & 0xFF, _id]);
            array_push(_list, ["adc_abs", _woff_addr + 1,             _id]);
            array_push(_list, ["sta_zp",  _wzp + 1,                   _id]);
            array_push(_list, ["ldy_imm", 0,                          _id]);
            array_push(_list, ["lda_izy", _wzp,                       _id]);
        } else {
            if (_woff_addr != 0) {
                array_push(_list, ["ldy_abs", _woff_addr, _id]);
            } else {
                if (_woff_mode == 1) {
                    show_debug_message("MACRO_SID_SOUND: wave offset var '" + _woff_var + "' unresolved; using index " + string(_woff_lit) + ".");
                }
                array_push(_list, ["ldy_imm", _woff_lit & 0xFF, _id]);
            }
            array_push(_list, ["lda_aby", _wave_ast_base, _id]);
        }
        // $FF = leave the control register alone.
        array_push(_list, ["cmp_imm", 0xFF,       _id]);
        array_push(_list, ["beq",     _lbl_wskip, _id]);
        array_push(_list, [_stop, _base + 4,      _id]);
        array_push(_list, ["label",   _lbl_wskip     ]);
    } else {
        if (_wave_mode == 1 && _wave_addr != 0) {
            array_push(_list, ["lda_abs", _wave_addr, _id]);
        } else {
            array_push(_list, ["lda_imm", _wave_lit,  _id]);
        }
        array_push(_list, [_stop, _base + 4, _id]);
    }
    if (_use_asset) {
        array_push(_list, ["label", _lbl_rest]);
    }
} break;

// --------------------------------------------------------
// MACRO_GET_CHAR
// Reads the screencode (and optionally colour) at row/col into
// named vars. Same shift-add pointer maths as MACRO_PLACE_CHAR.
// --------------------------------------------------------
case "MACRO_GET_CHAR": {
    var _id = _curr;
    var _i0 = _curr.instructions[0];

    var _col_lit   = (array_length(_i0) > 1  && is_real(_i0[1]))  ? real(_i0[1])  : 0;
    var _col_vmode = (array_length(_i0) > 2  && is_real(_i0[2]))  ? real(_i0[2])  : 0;
    var _col_var   = (array_length(_i0) > 3)  ? string(_i0[3])  : "";
    var _row_lit   = (array_length(_i0) > 4  && is_real(_i0[4]))  ? real(_i0[4])  : 0;
    var _row_vmode = (array_length(_i0) > 5  && is_real(_i0[5]))  ? real(_i0[5])  : 0;
    var _row_var   = (array_length(_i0) > 6)  ? string(_i0[6])  : "";
    var _dst_var   = (array_length(_i0) > 7)  ? string(_i0[7])  : "";
    var _get_col   = (array_length(_i0) > 8  && is_real(_i0[8]))  ? real(_i0[8])  : 0;
    var _dcol_var  = (array_length(_i0) > 9)  ? string(_i0[9])  : "";
    var _scr_base  = (array_length(_i0) > 10 && is_real(_i0[10])) ? real(_i0[10]) : 0x0400;
    var _zp        = (array_length(_i0) > 11 && is_real(_i0[11])) ? real(_i0[11]) : 0xFB;

    var _zp_sl = _zp;
    var _zp_sh = _zp + 1;
    var _zp_cl = _zp + 2;
    var _zp_ch = _zp + 3;

    var _col_addr  = scr_resolve_var_addr(_col_var);
    var _row_addr  = scr_resolve_var_addr(_row_var);
    var _dst_addr  = scr_resolve_var_addr(_dst_var);
    var _dcol_addr = scr_resolve_var_addr(_dcol_var);

    if (_dst_addr == 0) {
        show_debug_message("MACRO_GET_CHAR WARNING: dest var '" + _dst_var + "' not resolved.");
    }

    // ---- offset = row * 40 ----
    if (_row_vmode == 1 && _row_addr != 0) {
        array_push(_list, ["lda_abs", _row_addr, _id]);
    } else {
        array_push(_list, ["lda_imm", _row_lit & 0xFF, _id]);
    }
    array_push(_list, ["sta_zp",  _zp_sl, _id]);
    array_push(_list, ["lda_imm", 0,      _id]);
    array_push(_list, ["sta_zp",  _zp_sh, _id]);

    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);

    array_push(_list, ["lda_zp", _zp_sl, _id]);
    array_push(_list, ["sta_zp", _zp_cl, _id]);
    array_push(_list, ["lda_zp", _zp_sh, _id]);
    array_push(_list, ["sta_zp", _zp_ch, _id]);

    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);
    array_push(_list, ["asl_zp", _zp_sl, _id]);
    array_push(_list, ["rol_zp", _zp_sh, _id]);

    array_push(_list, ["clc",    0,      _id]);
    array_push(_list, ["lda_zp", _zp_sl, _id]);
    array_push(_list, ["adc_zp", _zp_cl, _id]);
    array_push(_list, ["sta_zp", _zp_sl, _id]);
    array_push(_list, ["lda_zp", _zp_sh, _id]);
    array_push(_list, ["adc_zp", _zp_ch, _id]);
    array_push(_list, ["sta_zp", _zp_sh, _id]);

    // + col
    array_push(_list, ["clc",    0,      _id]);
    array_push(_list, ["lda_zp", _zp_sl, _id]);
    if (_col_vmode == 1 && _col_addr != 0) {
        array_push(_list, ["adc_abs", _col_addr, _id]);
    } else {
        array_push(_list, ["adc_imm", _col_lit & 0xFF, _id]);
    }
    array_push(_list, ["sta_zp",  _zp_sl, _id]);
    array_push(_list, ["lda_zp",  _zp_sh, _id]);
    array_push(_list, ["adc_imm", 0,      _id]);
    array_push(_list, ["sta_zp",  _zp_sh, _id]);

    // colour ptr = offset + $D800
    if (_get_col == 1 && _dcol_addr != 0) {
        array_push(_list, ["clc",     0,      _id]);
        array_push(_list, ["lda_zp",  _zp_sl, _id]);
        array_push(_list, ["adc_imm", 0x00,   _id]);
        array_push(_list, ["sta_zp",  _zp_cl, _id]);
        array_push(_list, ["lda_zp",  _zp_sh, _id]);
        array_push(_list, ["adc_imm", 0xD8,   _id]);
        array_push(_list, ["sta_zp",  _zp_ch, _id]);
    }

    // screen ptr = offset + scr_base
    array_push(_list, ["clc",     0,                       _id]);
    array_push(_list, ["lda_zp",  _zp_sl,                  _id]);
    array_push(_list, ["adc_imm", _scr_base & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  _zp_sl,                  _id]);
    array_push(_list, ["lda_zp",  _zp_sh,                  _id]);
    array_push(_list, ["adc_imm", (_scr_base >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  _zp_sh,                  _id]);

    // ---- read ----
    array_push(_list, ["ldy_imm", 0,      _id]);
    array_push(_list, ["lda_izy", _zp_sl, _id]);
    if (_dst_addr != 0) {
        array_push(_list, ["sta_abs", _dst_addr, _id]);
    }

    if (_get_col == 1 && _dcol_addr != 0) {
        array_push(_list, ["lda_izy", _zp_cl,     _id]);
        array_push(_list, ["and_imm", 0x0F,       _id]);
        array_push(_list, ["sta_abs", _dcol_addr, _id]);
    }
} break;


// --------------------------------------------------------
// MACRO_DISPLAY
// Read-modify-write on $D011 bit 4 (DEN). Preserves every
// other bit in the register — safe alongside VSCROLL,
// bitmap mode, ECM and the 9th raster bit.
// Fixed cost: 8 bytes.
// --------------------------------------------------------
case "MACRO_DISPLAY": {
    var _id = _curr;
    var _dmode = 1;
    if (array_length(_curr.instructions[0]) > 1 && is_real(_curr.instructions[0][1])) {
        _dmode = real(_curr.instructions[0][1]);
    }
    array_push(_list, ["lda_abs", 0xD011, _id]);
    if (_dmode == 1) {
        array_push(_list, ["ora_imm", 0x10, _id]);   // set DEN
    } else {
        array_push(_list, ["and_imm", 0xEF, _id]);   // clear DEN
    }
    array_push(_list, ["sta_abs", 0xD011, _id]);
} break;


// --------------------------------------------------------
// MACRO_WAIT
// Blocking frame delay. Counts raster wraps at line $FF,
// gated on $D011 bit 8 (must be clear) so we only latch the
// top-frame instance of line 255, never its lower-border twin.
// Counter lives in X — no ZP touched. Clobbers A and X.
// Value is FRAMES: PAL 50/sec, NTSC 60/sec. Max 255 (5.1s PAL).
// LIT: 24 bytes.  VAR: 25 bytes.
// --------------------------------------------------------
case "MACRO_WAIT": {
    var _id = _curr;
    var _frames = 50;
    if (array_length(_curr.instructions[0]) > 1 && is_real(_curr.instructions[0][1])) {
        _frames = real(_curr.instructions[0][1]);
    }
    var _use_var = 0;
    if (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2])) {
        _use_var = real(_curr.instructions[0][2]);
    }
    var _vname = "";
    if (array_length(_curr.instructions[0]) > 3) {
        _vname = string(_curr.instructions[0][3]);
    }

    var _w_edge = "wait_edge_" + string(real(_id));
    var _w_top  = "wait_top_"  + string(real(_id));

    var _var_addr = 0;
    if (_use_var == 1 && _vname != "") {
        _var_addr = scr_resolve_var_addr(_vname);
        if (_var_addr == 0) {
            show_debug_message("MACRO_WAIT WARNING: var '" + _vname + "' not resolved.");
        }
    }

    // ---- Seed X with the frame count ----
    if (_use_var == 1 && _var_addr != 0) {
        array_push(_list, ["ldx_abs", _var_addr, _id]);
    } else {
        array_push(_list, ["ldx_imm", _frames & 0xFF, _id]);
    }

    // ---- Stage A: settle off line $FF (stops a double count on entry) ----
    array_push(_list, ["label",   _w_edge, _id]);
    array_push(_list, ["lda_abs", 0xD012,  _id]);
    array_push(_list, ["cmp_imm", 0xFF,    _id]);
    array_push(_list, ["beq",     _w_edge, _id]);

    // ---- Stage B: wait for line $FF with raster bit 8 clear ----
    array_push(_list, ["label",   _w_top,  _id]);
    array_push(_list, ["lda_abs", 0xD011,  _id]);
    array_push(_list, ["bmi",     _w_top,  _id]);
    array_push(_list, ["lda_abs", 0xD012,  _id]);
    array_push(_list, ["cmp_imm", 0xFF,    _id]);
    array_push(_list, ["bne",     _w_top,  _id]);

    // ---- One frame elapsed ----
    array_push(_list, ["dex", 0,       _id]);
    array_push(_list, ["bne", _w_edge, _id]);
} break;

// --------------------------------------------------------
// MACRO_VWAIT
// Raster sync, gated on D011 bit 8 so a single (<=255) line
// only matches in the top frame portion (0-255), never its
// phantom twin at 256-311 in the lower border.
// Fixed cost: literal 17 bytes, var 18 bytes.
// --------------------------------------------------------
case "MACRO_VWAIT": {
    var _id = _curr;
    var _line = 0xFB;
    if (is_real(_curr.instructions[0][1])) {
        _line = real(_curr.instructions[0][1]);
    }
    var _use_var = 0;
    if (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2])) {
        _use_var = real(_curr.instructions[0][2]);
    }
    var _vname = "";
    if (array_length(_curr.instructions[0]) > 3) {
        _vname = string(_curr.instructions[0][3]);
    }
    var _lo = "vwait_lo_" + string(real(_id));
    var _hi = "vwait_hi_" + string(real(_id));
    // Resolve var address if in var mode
    var _var_addr = 0;
    if (_use_var == 1 && _vname != "") {
        if (ds_map_exists(global.named_loc_map, _vname)) {
            _var_addr = ds_map_find_value(global.named_loc_map, _vname);
        }
        if (_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _vname) {
                    _var_addr = pc_address;
                    break;
                }
            }
        }
        if (_var_addr == 0) {
            show_debug_message("MACRO_VWAIT WARNING: var '" + _vname + "' not resolved.");
        }
    }
    if (_use_var == 1 && _var_addr != 0) {
        // VAR MODE: gate on D011 bit 8 (must be clear) so we only
        // match the target line in the top portion of the frame.
        array_push(_list, ["label",   _lo,       _id]);
        array_push(_list, ["lda_abs", 0xD011,    _id]);
        array_push(_list, ["bmi",     _lo,       _id]);
        array_push(_list, ["lda_abs", _var_addr, _id]);
        array_push(_list, ["cmp_abs", 0xD012,    _id]);
        array_push(_list, ["bne",     _lo,       _id]);
        // Stage two: settle until the raster ticks over to the next line
        array_push(_list, ["label",   _hi,       _id]);
        array_push(_list, ["cmp_abs", 0xD012,    _id]);
        array_push(_list, ["beq",     _hi,       _id]);
    } else {
        // LITERAL MODE — gate on D011 bit 8 (must be clear) so the line
        // only matches in the top portion of the frame, then settle.
        array_push(_list, ["label",   _lo,    _id]);
        array_push(_list, ["lda_abs", 0xD011, _id]);
        array_push(_list, ["bmi",     _lo,    _id]);
        array_push(_list, ["lda_imm", _line,  _id]);
        array_push(_list, ["cmp_abs", 0xD012, _id]);
        array_push(_list, ["bne",     _lo,    _id]);
        // Stage two: settle until the raster ticks over to the next line
        array_push(_list, ["label",   _hi,    _id]);
        array_push(_list, ["cmp_abs", 0xD012, _id]);
        array_push(_list, ["beq",     _hi,    _id]);
    }
} break;
						
// --------------------------------------------------------
// MACRO_MAP
// --------------------------------------------------------
case "MACRO_MAP": {
    var _id         = _curr;
    var _asset_name = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";
    var _base_addr  = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0x8000;

    // Resolve MAP_DATA asset
    var _map_w = 40;
    var _map_h = 25;
    var _scr_w = 40;
    var _scr_h = 25;
    var _col_row_start = (array_length(_curr.instructions[0]) > 5 && is_real(_curr.instructions[0][5])) ? clamp(real(_curr.instructions[0][5]), 0, 24) : 0;
    var _scroll_x = 0;
    var _scroll_y = 0;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                _base_addr = _a.address;
                if (variable_struct_exists(_a, "meta")) {
                    if (variable_struct_exists(_a.meta, "map_w"))    _map_w    = _a.meta.map_w;
                    if (variable_struct_exists(_a.meta, "map_h"))    _map_h    = _a.meta.map_h;
                    if (variable_struct_exists(_a.meta, "scroll_x")) _scroll_x = _a.meta.scroll_x;
                    if (variable_struct_exists(_a.meta, "scroll_y")) _scroll_y = _a.meta.scroll_y;
                }
                break;
            }
        }
    }

    // Resolve screen destination from MACRO_VIC node
	var _scr_dest = 0x0400;
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && org_parent == noone) {
            if (array_length(instructions[0]) > 3 && is_real(instructions[0][3]))
                _scr_dest = real(instructions[0][3]);
            break;
        }
    }

    var _char_src = _base_addr;
    var _col_src  = _base_addr + (_map_w * _map_h);

    var _csrc_lo   = _char_src & 0xFF;
    var _csrc_hi   = (_char_src >> 8) & 0xFF;
    var _colsrc_lo = _col_src & 0xFF;
    var _colsrc_hi = (_col_src >> 8) & 0xFF;

    // ZP base — user-configurable, default $50, occupies 4 bytes
    var _zp_base    = (array_length(_curr.instructions[0]) > 6 && is_real(_curr.instructions[0][6])) ? real(_curr.instructions[0][6]) : 0x50;
    var _zp_src_lo  = _zp_base;
    var _zp_src_hi  = _zp_base + 1;
    var _zp_col_lo  = _zp_base + 2;
    var _zp_col_hi  = _zp_base + 3;

    // Unique label prefix per node instance
    var _pfx = "mmap_" + string(real(_id)) + "_";

    var _lbl_sub      = _pfx + "sub";
    var _lbl_skip     = _pfx + "skip";
    var _lbl_chr_row  = _pfx + "cr";
    var _lbl_chr_inn  = _pfx + "ci";
    var _lbl_col_row  = _pfx + "lr";
    var _lbl_col_inn  = _pfx + "li";
    var _lbl_sy_loop  = _pfx + "syl";
    var _lbl_sy_done  = _pfx + "syd";
    var _lbl_sy_loop2 = _pfx + "syl2";
    var _lbl_sy_done2 = _pfx + "syd2";



    // ── 1. Init scroll ZP vars from compile-time values ──────────────
    // Runtime WASD can patch $F7/$F8/$F9 directly then JSR to subroutine
    /*
    array_push(_list, ["lda_imm", _scroll_x & 0xFF,         _id]);
    array_push(_list, ["sta_zp",  0xF7,                     _id]);  // scroll_x lo
    array_push(_list, ["lda_imm", (_scroll_x >> 8) & 0xFF,  _id]);
    array_push(_list, ["sta_zp",  0xF8,                     _id]);  // scroll_x hi
    array_push(_list, ["lda_imm", _scroll_y & 0xFF,         _id]);
    array_push(_list, ["sta_zp",  0xF9,                     _id]);  // scroll_y
    */

    // ── 2. Call subroutine once ───────────────────────────────────────
// Emit $D016 based on HR/Mixed mode — read from asset meta directly
var _map_mode = obj_workspace_manager.map_global_mixed;
var _d016_map = (_map_mode == 1) ? 0x18 : 0x08;

// Force flush before compile so buffer reflects current mode
if (instance_exists(obj_asset_manager) && _asset_name != "") {
    with (obj_asset_manager) {
        for (var _rfi = 0; _rfi < ds_list_size(asset_list); _rfi++) {
            var _rfa = ds_list_find_value(asset_list, _rfi);
            if (_rfa.type == "MAP_DATA" && _rfa.name == _asset_name) {
                scr_asset_map_flush(_rfa);
                break;
            }
        }
    }
}
    // $D016 handled after VIC mode switch below

// Resolve linked charset once — used to detect ECM and MC colour fallback
    var _map_chr_ref = noone;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                if (variable_struct_exists(_a.meta, "chr_asset") && _a.meta.chr_asset != "") {
                    var _chr_nm = _a.meta.chr_asset;
                    for (var _ci = 0; _ci < ds_list_size(_am.asset_list); _ci++) {
                        var _ca = ds_list_find_value(_am.asset_list, _ci);
                        if (_ca.type == "CHAR_SET" && _ca.name == _chr_nm) { _map_chr_ref = _ca; break; }
                    }
                }
                break;
            }
        }
    }
    var _map_is_ecm = (_map_chr_ref != noone) && variable_struct_exists(_map_chr_ref.meta, "mc_mode") && (_map_chr_ref.meta.mc_mode == 2);

    if (_map_is_ecm) {
        // ECM: all 4 VIC background registers come from the linked charset
        // (BG0 = mc_bg, BG1-3 = ecm_bg1/2/3). No per-map override yet.
        var _ecm_bg0 = variable_struct_exists(_map_chr_ref.meta, "mc_bg")   ? _map_chr_ref.meta.mc_bg   : 0;
        var _ecm_bg1 = variable_struct_exists(_map_chr_ref.meta, "ecm_bg1") ? _map_chr_ref.meta.ecm_bg1 : 6;
        var _ecm_bg2 = variable_struct_exists(_map_chr_ref.meta, "ecm_bg2") ? _map_chr_ref.meta.ecm_bg2 : 14;
        var _ecm_bg3 = variable_struct_exists(_map_chr_ref.meta, "ecm_bg3") ? _map_chr_ref.meta.ecm_bg3 : 3;
        array_push(_list, ["lda_imm", _ecm_bg0, _id]);
        array_push(_list, ["sta_abs", 0xD021,   _id]);
        array_push(_list, ["lda_imm", _ecm_bg1, _id]);
        array_push(_list, ["sta_abs", 0xD022,   _id]);
        array_push(_list, ["lda_imm", _ecm_bg2, _id]);
        array_push(_list, ["sta_abs", 0xD023,   _id]);
        array_push(_list, ["lda_imm", _ecm_bg3, _id]);
        array_push(_list, ["sta_abs", 0xD024,   _id]);
    } else if (_map_mode == 1 && instance_exists(obj_asset_manager) && _asset_name != "") {
        var _mc_bg   = 0;
        var _mc_col1 = 1;
        var _mc_col2 = 2;
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                if (variable_struct_exists(_a.meta, "map_mc_bg")   && _a.meta.map_mc_bg   >= 0) _mc_bg   = _a.meta.map_mc_bg;
                if (variable_struct_exists(_a.meta, "map_mc_col1") && _a.meta.map_mc_col1 >= 0) _mc_col1 = _a.meta.map_mc_col1;
                if (variable_struct_exists(_a.meta, "map_mc_col2") && _a.meta.map_mc_col2 >= 0) _mc_col2 = _a.meta.map_mc_col2;
                // Fall back to linked charset if map has no override
                if (_map_chr_ref != noone) {
                    if ((_mc_bg   == 0) && variable_struct_exists(_map_chr_ref.meta, "mc_bg"))   _mc_bg   = _map_chr_ref.meta.mc_bg;
                    if ((_mc_col1 == 1) && variable_struct_exists(_map_chr_ref.meta, "mc_col1")) _mc_col1 = _map_chr_ref.meta.mc_col1;
                    if ((_mc_col2 == 2) && variable_struct_exists(_map_chr_ref.meta, "mc_col2")) _mc_col2 = _map_chr_ref.meta.mc_col2;
                }
                break;
            }
        }
        array_push(_list, ["lda_imm", _mc_bg,   _id]);
        array_push(_list, ["sta_abs", 0xD021,    _id]);
        array_push(_list, ["lda_imm", _mc_col1,  _id]);
        array_push(_list, ["sta_abs", 0xD022,    _id]);
		
array_push(_list, ["lda_imm", _mc_col2,  _id]);
        array_push(_list, ["sta_abs", 0xD023,    _id]);
    } // <-- This bracket closes the MC/ECM colour setup

// ── Zero scroll ZP vars — subroutine reads $F7/$F8/$F9 for scroll offset ──
    array_push(_list, ["lda_imm", 0x00,   _id]);
    array_push(_list, ["sta_zp",  0xF7,   _id]); // scroll_x lo
    array_push(_list, ["sta_zp",  0xF8,   _id]); // scroll_x hi
    array_push(_list, ["sta_zp",  0xF9,   _id]); // scroll_y

    // Check if MACRO_SCROLL is present — it owns VIC init so we skip the mode switch
    var _map_has_scroll = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SCROLL" && is_connected)
        {
            _map_has_scroll = true;
            break;
        }
    }

    // Check if a CHAR_SET node exists in the compile chain
    // If not, emit $D018 ourselves using the charset linked in the map asset
    var _map_chr_node_exists = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_CHR" && is_connected)
        {
            _map_chr_node_exists = true;
            break;
        }
    }


// $D018 emit removed — MACRO_VIC and MACRO_CHR own this register.
    // Calculating it from the map's linked charset risks bank inconsistency
    // when the actual VIC bank differs from the charset's stored vic_bank meta.

   // Write char source address into ZP pointer pair
    array_push(_list, ["lda_imm", _char_src & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  _zp_src_lo,              _id]);
    array_push(_list, ["lda_imm", (_char_src >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  _zp_src_hi,              _id]);
    // Write colour source address into ZP pointer pair
    array_push(_list, ["lda_imm", _col_src & 0xFF,         _id]);
    array_push(_list, ["sta_zp",  _zp_col_lo,              _id]);
    array_push(_list, ["lda_imm", (_col_src >> 8) & 0xFF,  _id]);
    array_push(_list, ["sta_zp",  _zp_col_hi,              _id]);

    // Disable IRQs around the copy — SID play routine clobbers ZP $E3/$E4/$FB/$FC
    // which MACRO_MAP uses as source/dest pointers for the (zp),Y copy
    array_push(_list, ["sei",     0,                   _id]);
    array_push(_list, ["jsr",     _lbl_sub,            _id]);
    array_push(_list, ["cli",     0,                   _id]);

    // VIC mode switch removed — MACRO_VIC owns $D011 and $D016.
    // MACRO_MAP is purely a data copy, no register management.
	
	
    array_push(_list, ["jmp_abs", _lbl_skip,           _id]);

    // ── 3. SUBROUTINE ─────────────────────────────────────────────────
    // map_redraw: shared callable label — MACRO_MAP_SWITCH and MAP_OFFSET JSR here
    array_push(_list, ["label",   "map_redraw"                   ]);
    array_push(_list, ["label",   _lbl_sub                       ]);

    // CHAR BLOCK: zp_src (runtime pointer) + scroll_x ($F7/$F8) + scroll_y*map_w ($F9) → $FB/$FC
    array_push(_list, ["lda_zp",  _zp_src_lo,               _id]);  // char base lo (runtime)
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_zp",  0xF7,                     _id]);  // + scroll_x lo
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  _zp_src_hi,               _id]);  // char base hi (runtime)
    array_push(_list, ["adc_zp",  0xF8,                     _id]);  // + scroll_x hi + carry
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    // Add scroll_y * map_w
    array_push(_list, ["lda_zp",  0xF9,                     _id]);  // scroll_y
    array_push(_list, ["beq",     _lbl_sy_done,             _id]);
    array_push(_list, ["tax",     0,                        _id]);
    array_push(_list, ["label",   _lbl_sy_loop                  ]);
    array_push(_list, ["lda_zp",  0xFB,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _map_w & 0xFF,            _id]);
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  0xFC,                     _id]);
    array_push(_list, ["adc_imm", (_map_w >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    array_push(_list, ["dex",     0,                        _id]);
    array_push(_list, ["bne",     _lbl_sy_loop,             _id]);
    array_push(_list, ["label",   _lbl_sy_done                  ]);
    // Screen dest → $E3/$E4
    array_push(_list, ["lda_imm", _scr_dest & 0xFF,         _id]);
    array_push(_list, ["sta_zp",  0xE3,                     _id]);
    array_push(_list, ["lda_imm", (_scr_dest >> 8) & 0xFF,  _id]);
    array_push(_list, ["sta_zp",  0xE4,                     _id]);
    // Row copy
    array_push(_list, ["ldx_imm", _scr_h,                   _id]);
    array_push(_list, ["label",   _lbl_chr_row                  ]);
    array_push(_list, ["ldy_imm", 0,                        _id]);
    array_push(_list, ["label",   _lbl_chr_inn                  ]);
    array_push(_list, ["lda_izy", 0xFB,                     _id]);
    array_push(_list, ["sta_izy", 0xE3,                     _id]);
    array_push(_list, ["iny",     0,                        _id]);
    array_push(_list, ["cpy_imm", _scr_w,                   _id]);
    array_push(_list, ["bne",     _lbl_chr_inn,             _id]);
    array_push(_list, ["lda_zp",  0xFB,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _map_w & 0xFF,            _id]);
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  0xFC,                     _id]);
    array_push(_list, ["adc_imm", (_map_w >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    array_push(_list, ["lda_zp",  0xE3,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _scr_w,                   _id]);
    array_push(_list, ["sta_zp",  0xE3,                     _id]);
    array_push(_list, ["lda_zp",  0xE4,                     _id]);
    array_push(_list, ["adc_imm", 0,                        _id]);
    array_push(_list, ["sta_zp",  0xE4,                     _id]);
    array_push(_list, ["dex",     0,                        _id]);
    array_push(_list, ["bne",     _lbl_chr_row,             _id]);

    // COLOUR BLOCK: zp_col (runtime pointer) + scroll_x + scroll_y*map_w → $FB/$FC
    array_push(_list, ["lda_zp",  _zp_col_lo,               _id]);  // col base lo (runtime)
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_zp",  0xF7,                     _id]);  // + scroll_x lo
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  _zp_col_hi,               _id]);  // col base hi (runtime)
    array_push(_list, ["adc_zp",  0xF8,                     _id]);  // + scroll_x hi + carry
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    // Add scroll_y * map_w
    array_push(_list, ["lda_zp",  0xF9,                     _id]);
    array_push(_list, ["beq",     _lbl_sy_done2,            _id]);
    array_push(_list, ["tax",     0,                        _id]);
    array_push(_list, ["label",   _lbl_sy_loop2                 ]);
    array_push(_list, ["lda_zp",  0xFB,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _map_w & 0xFF,            _id]);
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  0xFC,                     _id]);
    array_push(_list, ["adc_imm", (_map_w >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    array_push(_list, ["dex",     0,                        _id]);
    array_push(_list, ["bne",     _lbl_sy_loop2,            _id]);
    array_push(_list, ["label",   _lbl_sy_done2                 ]);
    // Dest = $D800 + col_row_start*40 → $E3/$E4
    var _col_dest     = 0xD800 + (_col_row_start * 40);
    var _col_src_skip = _col_row_start; // rows to skip in source
    // Advance source pointer by _col_row_start rows
    if (_col_src_skip > 0) {
        array_push(_list, ["lda_zp",  0xFB,                                    _id]);
        array_push(_list, ["clc",     0,                                        _id]);
        array_push(_list, ["adc_imm", (_map_w * _col_src_skip) & 0xFF,         _id]);
        array_push(_list, ["sta_zp",  0xFB,                                    _id]);
        array_push(_list, ["lda_zp",  0xFC,                                    _id]);
        array_push(_list, ["adc_imm", ((_map_w * _col_src_skip) >> 8) & 0xFF,  _id]);
        array_push(_list, ["sta_zp",  0xFC,                                    _id]);
    }
    array_push(_list, ["lda_imm", _col_dest & 0xFF,                            _id]);
    array_push(_list, ["sta_zp",  0xE3,                                        _id]);
    array_push(_list, ["lda_imm", (_col_dest >> 8) & 0xFF,                     _id]);
    array_push(_list, ["sta_zp",  0xE4,                                        _id]);
    // Row copy — only rows from col_row_start onwards
    array_push(_list, ["ldx_imm", _scr_h - _col_row_start,                     _id]);
    array_push(_list, ["label",   _lbl_col_row                  ]);
    array_push(_list, ["ldy_imm", 0,                        _id]);
    array_push(_list, ["label",   _lbl_col_inn                  ]);
    array_push(_list, ["lda_izy", 0xFB,                     _id]);
    array_push(_list, ["sta_izy", 0xE3,                     _id]);
    array_push(_list, ["iny",     0,                        _id]);
    array_push(_list, ["cpy_imm", _scr_w,                   _id]);
    array_push(_list, ["bne",     _lbl_col_inn,             _id]);
    array_push(_list, ["lda_zp",  0xFB,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _map_w & 0xFF,            _id]);
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_zp",  0xFC,                     _id]);
    array_push(_list, ["adc_imm", (_map_w >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_zp",  0xFC,                     _id]);
    array_push(_list, ["lda_zp",  0xE3,                     _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _scr_w,                   _id]);
    array_push(_list, ["sta_zp",  0xE3,                     _id]);
    array_push(_list, ["lda_zp",  0xE4,                     _id]);
    array_push(_list, ["adc_imm", 0,                        _id]);
    array_push(_list, ["sta_zp",  0xE4,                     _id]);
    array_push(_list, ["dex",     0,                        _id]);
    array_push(_list, ["bne",     _lbl_col_row,             _id]);

    array_push(_list, ["rts",     0,                       _id]);

    // ── 4. SKIP LANDING ───────────────────────────────────────────────
    array_push(_list, ["label",   _lbl_skip                     ]);

} break;


// --------------------------------------------------------
// MACRO_METAMAP — flatten a META_TILESET map to screen
// instructions[0]: ["macro_metamap", tileset_name, map_index, base_addr, col_row_start, zp_base, src_mode, map_var]
//
// LIT mode (src_mode 0): flattens the chosen map to a 40x25 char+colour plane
// at base_addr (planes via org save/restore), then copies to screen with a
// MACRO_MAP-style (zp),Y loop. Emits <tileset>_TILE_TYPES for COLL_ADV.
//
// VAR mode (src_mode 1): injects EVERY room as a placement list
// [ (stamp,gx,gy)... , $FF ] off-spine, a MAPPTR_LO/HI table indexed by the
// byte var, and a stamp-def table (char,colour per cell). A runtime stamper
// on the node reads the var, walks that room's list, and stamps each metatile
// to screen+$D800. Re-running the node redraws whatever room the var holds.
// stamp_w/stamp_h are baked as compile-time constants.
// --------------------------------------------------------
case "MACRO_METAMAP": {
    var _id            = _curr;
    var _tileset_name  = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";
    var _map_index     = (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2])) ? real(_curr.instructions[0][2]) : 0;
    var _base_addr     = (array_length(_curr.instructions[0]) > 3 && is_real(_curr.instructions[0][3])) ? real(_curr.instructions[0][3]) : 0x8000;
    var _col_row_start = (array_length(_curr.instructions[0]) > 4 && is_real(_curr.instructions[0][4])) ? clamp(real(_curr.instructions[0][4]), 0, 24) : 0;
    if (array_length(_curr.instructions[0]) > 6 && is_string(_curr.instructions[0][6])) {
        var _mm_stray = _curr.instructions[0][6];
        while (array_length(_curr.instructions[0]) < 8) array_push(_curr.instructions[0], "");
        _curr.instructions[0][7] = _mm_stray;
        _curr.instructions[0][6] = 1;
    }
    var _mm_src_mode   = (array_length(_curr.instructions[0]) > 6 && is_real(_curr.instructions[0][6])) ? real(_curr.instructions[0][6]) : 0;
    var _mm_map_var    = (array_length(_curr.instructions[0]) > 7) ? string(_curr.instructions[0][7]) : "";

    // Resolve the META_TILESET asset
    var _ts = noone;
    if (_tileset_name != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "META_TILESET" && _a.name == _tileset_name) { _ts = _a; break; }
        }
    }
    if (_ts == noone) {
        show_debug_message("MACRO_METAMAP: tileset '" + _tileset_name + "' not found — skipping");
        break;
    }

    var _tm         = _ts.meta;
    var _sw         = _tm.stamp_w;
    var _sh         = _tm.stamp_h;
    var _stamp_data = _tm.stamp_data;
    var _cells_per  = _sw * _sh;

    // Resolve linked charset once — used to detect ECM and MC colour fallback
    var _mm_chr_ref = noone;
    if (variable_struct_exists(_tm, "chr_asset") && _tm.chr_asset != "" && instance_exists(obj_asset_manager)) {
        var _mm_amc = obj_asset_manager;
        for (var _mmci = 0; _mmci < ds_list_size(_mm_amc.asset_list); _mmci++) {
            var _mmca = ds_list_find_value(_mm_amc.asset_list, _mmci);
            if (_mmca.type == "CHAR_SET" && _mmca.name == _tm.chr_asset) { _mm_chr_ref = _mmca; break; }
        }
    }
    var _mm_is_ecm = (_mm_chr_ref != noone) && variable_struct_exists(_mm_chr_ref.meta, "mc_mode") && (_mm_chr_ref.meta.mc_mode == 2);

    // Resolve which grid this map_index points at
    var _grid = noone;
    if (_map_index >= 0 && _map_index < _tm.map_count) {
        _grid = _tm.maps[_map_index];
    }
    if (_grid == noone) {
        show_debug_message("MACRO_METAMAP: map index " + string(_map_index) + " out of range — skipping");
        break;
    }

    var _lit_w_ch = 40;
    if (_map_index >= 0 && _map_index < array_length(_tm.map_w))
    {
        _lit_w_ch = _tm.map_w[_map_index];
    }
    var _cols = floor(_lit_w_ch / _sw);
    if (_cols < 1)
    {
        _cols = 1;
    }
    var _rows = floor(array_length(_grid) / _cols);

    // Global mixed mode — masks colour the same way the editor preview does
    var _mm_mode = obj_workspace_manager.map_global_mixed;

    // Build 40x25 char + colour planes; default char 0 / colour 0
    var _char_plane = array_create(40 * 25, 0);
    var _col_plane  = array_create(40 * 25, 0);

    for (var _gy = 0; _gy < _rows; _gy++) {
        for (var _gx = 0; _gx < _cols; _gx++) {
            var _mt = _grid[_gy * _cols + _gx];
            if (_mt < 0) continue;
            if (_mt >= _tm.stamp_count) continue;
            for (var _cy2 = 0; _cy2 < _sh; _cy2++) {
                for (var _cx2 = 0; _cx2 < _sw; _cx2++) {
                   var _cell      = _cy2 * _sw + _cx2;
                    var _data_base = (_mt * _cells_per + _cell);   // 1 byte/cell (char only)
                    if (_data_base >= array_length(_stamp_data)) continue;
                    var _ch   = _stamp_data[_data_base];
                    // Colour comes from char_lut[char] (bits 0-3), NOT stamp_data.
                    var _col  = (_ch < array_length(_tm.char_lut)) ? (_tm.char_lut[_ch] & 0x0F) : 0;
                    // Per-stamp colour override: if not $80, force this colour on every cell of the stamp.
                    var _ov_col = (variable_struct_exists(_tm, "stamp_override")
                                && _mt < array_length(_tm.stamp_override)
                                && _tm.stamp_override[_mt] != 0x80)
                                ? _tm.stamp_override[_mt] : -1;
                    if (_ov_col >= 0) _col = _ov_col;
                    // Mode is per-char via char_lut bit 4 (0 = HR, 1 = MC), not per-stamp.
                    var _mt_is_mc = (_mm_mode == 1
                                  && _ch < array_length(_tm.char_lut)
                                  && ((_tm.char_lut[_ch] >> 4) & 0x01) == 1);
                    var _mcol;
                    if (_mm_is_ecm) {
                        _mcol = _col & 0x0F;          // ECM: always full nibble, never masked/MC-flagged
                    } else if (_mm_mode == 0) {
                        _mcol = _col & 0x0F;          // HR16: full nibble
                    } else if (_mt_is_mc) {
                        _mcol = (_col & 0x07) | 0x08; // MC: bit 3 set
                    } else {
                        _mcol = _col & 0x07;          // HR cell in mixed map
                    }
                    var _scr_col = _gx * _sw + _cx2;
                    var _scr_row = _gy * _sh + _cy2;
                    if (_scr_col >= 40 || _scr_row >= 25) continue;
                    var _idx = _scr_row * 40 + _scr_col;
                    _char_plane[_idx] = _ch;
                    _col_plane[_idx]  = _mcol;
                }
            }
        }
    }

    // ============================================================
    // VAR MODE — inject all rooms + pointer tables + runtime stamper
    // Uses ONLY confirmed opcodes (see scr_define_opcodes):
    //   byte_lab_lo / byte_lab_hi  → emit lo/hi byte of a label addr
    //   lda_lab_lo  / lda_lab_hi   → load lo/hi byte of a label as immediate
    //   lda_abx (label),X          → indexed table read
    // No runtime multiplies: STAMPDEF_LO/HI and ROWMUL are compile-time tables.
    // ============================================================
    if (_mm_src_mode == 1) {
        // Resolve the map-number byte var address
        var _mm_var_addr = -1;
        if (_mm_map_var != "" && ds_map_exists(global.named_loc_map, _mm_map_var)) {
            _mm_var_addr = ds_map_find_value(global.named_loc_map, _mm_map_var);
        }
        if (_mm_var_addr < 0) {
            show_debug_message("MACRO_METAMAP(VAR): map var '" + _mm_map_var + "' not resolved — skipping");
            break;
        }

        var _vpfx     = "mmv_" + string(real(_id)) + "_";
        var _map_cnt  = _tm.map_count;
        var _cells_pr = _sw * _sh;  // cells per stamp

        // ── Off-spine data block: stamp-def, stamp ptr table, rooms, room ptr table, ROWMUL ──
        array_push(_list, ["org", -2]);
        array_push(_list, ["org", _base_addr]);

        var _vid_save = _id;
        var _id = noone; // suppress node tagging on org-bracketed data

        // 1) STAMP-DEF cell tables: per stamp, _cells_pr * (char, colour).
        //    One label per stamp so the pointer table can reference it.
        //    In MIXED mode, MC stamps get colour-RAM bit 3 set (| 0x08) so VIC
        //    renders them multicolour; HR stamps keep the clean 0x07 nibble.
        for (var _sd = 0; _sd < _tm.stamp_count; _sd++) {
            // Per-stamp colour override: if not $80, force this colour on every cell.
            var _sd_ov = (variable_struct_exists(_tm, "stamp_override")
                       && _sd < array_length(_tm.stamp_override)
                       && _tm.stamp_override[_sd] != 0x80)
                       ? _tm.stamp_override[_sd] : -1;
            array_push(_list, ["label", _vpfx + "sd_" + string(_sd)]);
            for (var _sc = 0; _sc < _cells_pr; _sc++) {
                var _sdb = (_sd * _cells_pr + _sc);   // 1 byte/cell (char only)
                var _sch = 0;
                var _scl = 0;
                if (_sdb < array_length(_stamp_data)) {
                    _sch = _stamp_data[_sdb];
                    // Colour from char_lut[char] (bits 0-3), override wins.
                    // Mode is per-char via char_lut bit 4 (0 = HR, 1 = MC), not per-stamp.
                    var _cell_is_mc = (_mm_mode == 1
                                    && _sch < array_length(_tm.char_lut)
                                    && ((_tm.char_lut[_sch] >> 4) & 0x01) == 1);
                    if (_mm_is_ecm) {
                        _scl = _raw_col & 0x0F;          // ECM: always full nibble, never masked/MC-flagged
                    } else if (_mm_mode == 0) {
                        _scl = _raw_col & 0x0F;          // HR16: full nibble
                    } else if (_cell_is_mc) {
                        _scl = (_raw_col & 0x07) | 0x08; // MC: bit 3 set
                    } else {
                        _scl = _raw_col & 0x07;          // HR cell in mixed map
                    }
                }
                array_push(_list, ["byte", _sch & 0xFF]);
                array_push(_list, ["byte", _scl & 0xFF]);
            }
        }

        // 2) STAMPDEF pointer table — STAMPDEF_LO/HI[stamp] -> sd_<stamp>
        array_push(_list, ["label", _vpfx + "stampdef_lo"]);
        for (var _sp = 0; _sp < _tm.stamp_count; _sp++) {
            array_push(_list, ["byte_lab_lo", _vpfx + "sd_" + string(_sp)]);
        }
        array_push(_list, ["label", _vpfx + "stampdef_hi"]);
        for (var _sq = 0; _sq < _tm.stamp_count; _sq++) {
            array_push(_list, ["byte_lab_hi", _vpfx + "sd_" + string(_sq)]);
        }

        // 3) ROOM LISTS: each [ (stamp,gx,gy)... , $FF ]. Label per room.
        //    Stride is THIS room's stored width, not the screen width. Rooms
        //    may be narrower than 40 chars, so floor(40/_sw) would over-read
        //    each row and drop its last real column. map_w[] holds char width
        //    and is parallel to maps[]; rows come from the grid length.
        for (var _rm = 0; _rm < _map_cnt; _rm++)
        {
            array_push(_list, ["label", _vpfx + "room_" + string(_rm)]);
            var _rgrid = _tm.maps[_rm];
            var _rmw_ch = 40;
            if (_rm < array_length(_tm.map_w))
            {
                _rmw_ch = _tm.map_w[_rm];
            }
            var _cols_v = floor(_rmw_ch / _sw);
            if (_cols_v < 1)
            {
                _cols_v = 1;
            }
            var _rows_v = floor(array_length(_rgrid) / _cols_v);
            for (var _ry = 0; _ry < _rows_v; _ry++)
            {
                // Skip a metatile only when its TOP cell-row is already off the
                // 25-row screen. The runtime stamper seeds its screen pointer
                // from COLL_ROW_LO/HI (25 entries, rows 0-24) using the TOP row,
                // then advances $E3/$E4 by 40 per cell-row from there — so once
                // the top row is a valid 0-24 index, the remaining cell-rows walk
                // forward correctly even if the bottom spills past row 24. A tile
                // straddling the bottom edge therefore draws its on-screen rows
                // and lets the rest write harmlessly past screen RAM (the sprite
                // save/restore already guards $07F8-$07FF). Only when the TOP row
                // itself is >= 25 would we index past the LUT and scatter cells.
                var _top_row = _ry * _sh;
                if (_top_row > 24)
                {
                    continue;
                }
                for (var _rx = 0; _rx < _cols_v; _rx++)
                {
                    var _rcell = _rgrid[(_ry * _cols_v) + _rx];
                    if (_rcell < 0)
                    {
                        continue;
                    }
                    if (_rcell >= 255)
                    {
                        show_debug_message("MACRO_METAMAP(VAR): room " + string(_rm) + " stamp idx >= 255 clashes with $FF sentinel");
                        continue;
                    }
                    array_push(_list, ["byte", _rcell & 0xFF]);
                    array_push(_list, ["byte", _rx & 0xFF]);
                    array_push(_list, ["byte", _ry & 0xFF]);
                }
            }
            array_push(_list, ["byte", 0xFF]); // room terminator
        }

        // 4) ROOM pointer table — MAPPTR_LO/HI[room] -> room_<room>
        array_push(_list, ["label", _vpfx + "mapptr_lo"]);
        for (var _pl = 0; _pl < _map_cnt; _pl++) {
            array_push(_list, ["byte_lab_lo", _vpfx + "room_" + string(_pl)]);
        }
        array_push(_list, ["label", _vpfx + "mapptr_hi"]);
        for (var _ph = 0; _ph < _map_cnt; _ph++) {
            array_push(_list, ["byte_lab_hi", _vpfx + "room_" + string(_ph)]);
        }

        // 5) ROWMUL table — ROWMUL[gy] = gy * _sh. Sized to the screen's full
        //    metatile-row count so it covers the tallest possible room (rooms
        //    may now differ in height). gy values past a given room's height
        //    simply never get indexed at runtime.
        var _rowmul_n = floor(25 / _sh) + 1;
        array_push(_list, ["label", _vpfx + "rowmul"]);
        for (var _rmul = 0; _rmul < _rowmul_n; _rmul++) {
            array_push(_list, ["byte", (_rmul * _sh) & 0xFF]);
        }

        // 6) SPRITE-POINTER SAVE buffer — 8 bytes. The stamper backs up the
        //    sprite pointers (screen_base+$3F8..$3FF) here before drawing, then
        //    restores them after, so a bottom-row metatile spilling into that
        //    region can't blank the sprites.
        array_push(_list, ["label", _vpfx + "spsave"]);
        for (var _spz = 0; _spz < 8; _spz++) {
            array_push(_list, ["byte", 0x00]);
        }

        array_push(_list, ["org", -3]); // restore spine PC
        var _id = _vid_save;

        // ── Ensure COLL_ROW_LO/HI exist (stamper indexes them by screen row) ──
        if (!variable_global_exists("coll_row_luts_emitted") || global.coll_row_luts_emitted == false) {
            array_push(_list, ["jmp_abs", _vpfx + "lutskip", _id]);
            array_push(_list, ["label", "COLL_ROW_LO"]);
            var _vrow_lo = [0x00,0x28,0x50,0x78,0xA0,0xC8,0xF0,0x18,0x40,0x68,0x90,0xB8,0xE0,0x08,0x30,0x58,0x80,0xA8,0xD0,0xF8,0x20,0x48,0x70,0x98,0xC0];
            for (var _vri = 0; _vri < 25; _vri++) array_push(_list, ["byte", _vrow_lo[_vri], _id]);
            array_push(_list, ["label", "COLL_ROW_HI"]);
            var _vrow_hi = [0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x05,0x05,0x05,0x05,0x05,0x05,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x07,0x07,0x07,0x07,0x07];
            for (var _vri = 0; _vri < 25; _vri++) array_push(_list, ["byte", _vrow_hi[_vri], _id]);
            array_push(_list, ["label", _vpfx + "lutskip"]);
            global.coll_row_luts_emitted = true;
        }

        // COLL_COL_HI — colour-RAM hi byte per screen row ($D8-based). Emitted
        // under its OWN guard because COLL_ROW_LO/HI may have been emitted by a
        // different node (LIT metamap / COLL path) that doesn't emit this table.
        // Same low byte as COLL_ROW_LO; hi = COLL_ROW_HI[row] - $04 + $D8.
        if (!variable_global_exists("coll_col_hi_emitted") || global.coll_col_hi_emitted == false) {
            array_push(_list, ["jmp_abs", _vpfx + "colskip", _id]);
            array_push(_list, ["label", "COLL_COL_HI"]);
            var _vcol_hi = [0xD8,0xD8,0xD8,0xD8,0xD8,0xD8,0xD8,0xD9,0xD9,0xD9,0xD9,0xD9,0xD9,0xDA,0xDA,0xDA,0xDA,0xDA,0xDA,0xDA,0xDB,0xDB,0xDB,0xDB,0xDB];
            for (var _vri = 0; _vri < 25; _vri++) array_push(_list, ["byte", _vcol_hi[_vri], _id]);
            array_push(_list, ["label", _vpfx + "colskip"]);
            global.coll_col_hi_emitted = true;
        
        }

        // ── Resolve screen destination (same as LIT/MACRO_MAP) ──
        var _v_scr = 0x0400;
        with (obj_c64_node) {
            if (node_type == "MACRO_VIC" && org_parent == noone) {
                if (array_length(instructions[0]) > 3 && is_real(instructions[0][3]))
                    _v_scr = real(instructions[0][3]);
                break;
            }
        }

        // ── VIC background colours: ECM (4 registers) or MC (mixed mode) ──
        if (_mm_is_ecm) {
            var _v_ecm_bg0 = variable_struct_exists(_mm_chr_ref.meta, "mc_bg")   ? _mm_chr_ref.meta.mc_bg   : 0;
            var _v_ecm_bg1 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg1") ? _mm_chr_ref.meta.ecm_bg1 : 6;
            var _v_ecm_bg2 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg2") ? _mm_chr_ref.meta.ecm_bg2 : 14;
            var _v_ecm_bg3 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg3") ? _mm_chr_ref.meta.ecm_bg3 : 3;
            array_push(_list, ["lda_imm", _v_ecm_bg0, _id]);
            array_push(_list, ["sta_abs", 0xD021,     _id]);
            array_push(_list, ["lda_imm", _v_ecm_bg1, _id]);
            array_push(_list, ["sta_abs", 0xD022,     _id]);
            array_push(_list, ["lda_imm", _v_ecm_bg2, _id]);
            array_push(_list, ["sta_abs", 0xD023,     _id]);
            array_push(_list, ["lda_imm", _v_ecm_bg3, _id]);
            array_push(_list, ["sta_abs", 0xD024,     _id]);
        } else if (_mm_mode == 1) {
            var _vmc_bg   = (variable_struct_exists(_tm, "map_mc_bg")   && _tm.map_mc_bg   >= 0) ? _tm.map_mc_bg   : 0;
            var _vmc_col1 = (variable_struct_exists(_tm, "map_mc_col1") && _tm.map_mc_col1 >= 0) ? _tm.map_mc_col1 : 1;
            var _vmc_col2 = (variable_struct_exists(_tm, "map_mc_col2") && _tm.map_mc_col2 >= 0) ? _tm.map_mc_col2 : 2;
            array_push(_list, ["lda_imm", _vmc_bg,   _id]);
            array_push(_list, ["sta_abs", 0xD021,    _id]);
            array_push(_list, ["lda_imm", _vmc_col1, _id]);
            array_push(_list, ["sta_abs", 0xD022,    _id]);
            array_push(_list, ["lda_imm", _vmc_col2, _id]);
            array_push(_list, ["sta_abs", 0xD023,    _id]);
            // Enable VIC-II multicolour text mode (set $D016 bit 4)
            array_push(_list, ["lda_abs", 0xD016, _id]);
            array_push(_list, ["ora_imm", 0x10,   _id]);
            array_push(_list, ["sta_abs", 0xD016, _id]);
        }

        // ────────────────────────────────────────────────────────────
       // ────────────────────────────────────────────────────────────
// RUNTIME STAMPER  (no multiplies — all via tables)
// $FB/$FC room-list ptr (ADVANCES per triplet, so rooms may exceed 255 bytes)
// $E3/$E4 screen   $22/$23 colour   $24/$25 stamp-def ptr   $FD gx*sw
// Y only ever ranges 0..2 within a triplet — no 8-bit overflow on big rooms.
// ────────────────────────────────────────────────────────────
var _L_next = _vpfx + "next";
var _L_done = _vpfx + "done";
var _L_body = _vpfx + "body";

array_push(_list, ["sei", 0, _id]);

// ── Back up the 8 sprite pointers (screen_base+$3F8) before stamping ──
var _v_sptr = _v_scr + 0x3F8;
array_push(_list, ["ldx_imm", 0x00,             _id]);
array_push(_list, ["label",   _vpfx + "spbk"]);
array_push(_list, ["lda_abx", _v_sptr,          _id]); // numeric base + X
array_push(_list, ["sta_abx", _vpfx + "spsave", _id]); // label base + X
array_push(_list, ["inx",     0,                _id]);
array_push(_list, ["cpx_imm", 0x08,             _id]);
array_push(_list, ["bne",     _vpfx + "spbk",   _id]);

// ── Clear screen RAM only before stamping. VAR writes only the occupied
// cells (unlike LIT's full 1000-byte copy), so previous screen contents
// (e.g. the BASIC startup banner) would show through the gaps. Colour RAM
// is NOT cleared: this is a static, non-scrolling draw and every char cell
// the stamper writes also writes its colour cell in lockstep, so stale
// colour under a space ($20) is never visible.
//
// Pages 0-2 fill in full via the wrapping bne loop. The fourth page stops at
// $07E8 (232 bytes) so the fill never touches the sprite pointer table at
// $07F8-$07FF. Clearing those first would blank the pointers BEFORE the
// spbk backup reads them, so the restore would write garbage back and the
// sprites would clobber between rooms. Skipping them here keeps the backup/
// restore bracket doing only its real job: guarding against stamp overspill.
array_push(_list, ["lda_imm", 0x20,               _id]);
array_push(_list, ["ldx_imm", 0x00,               _id]);
array_push(_list, ["label",   _vpfx + "clrscr"]);
array_push(_list, ["sta_abx", _v_scr,             _id]);
array_push(_list, ["sta_abx", _v_scr + 0x100,     _id]);
array_push(_list, ["sta_abx", _v_scr + 0x200,     _id]);
array_push(_list, ["inx",     0,                  _id]);
array_push(_list, ["bne",     _vpfx + "clrscr",   _id]);
array_push(_list, ["ldx_imm", 0x00,               _id]);
array_push(_list, ["label",   _vpfx + "clrscr_p3"]);
array_push(_list, ["sta_abx", _v_scr + 0x300,     _id]);
array_push(_list, ["inx",     0,                  _id]);
array_push(_list, ["cpx_imm", 0xE8,               _id]);
array_push(_list, ["bne",     _vpfx + "clrscr_p3", _id]);

// room ptr = MAPPTR[var]
array_push(_list, ["ldx_abs", _mm_var_addr,        _id]);
array_push(_list, ["lda_abx", _vpfx + "mapptr_lo", _id]);
array_push(_list, ["sta_zp",  0xFB,                _id]);
array_push(_list, ["lda_abx", _vpfx + "mapptr_hi", _id]);
array_push(_list, ["sta_zp",  0xFC,                _id]);

// ── per-placement loop ──
// Each entry is 3 bytes: stamp, gx, gy. We read at Y=0,1,2 then add 3 to the
// 16-bit base pointer $FB/$FC and loop with Y reset to 0. This keeps Y tiny
// regardless of room size (burger-time rooms are ~720 bytes — far past 255).
array_push(_list, ["label",   _L_next]);
array_push(_list, ["ldy_imm", 0x00,    _id]); // Y = 0 at each triplet start
array_push(_list, ["lda_izy", 0xFB,    _id]); // A = stamp idx
array_push(_list, ["cmp_imm", 0xFF,    _id]); // sentinel?
array_push(_list, ["bne",     _L_body, _id]); // not sentinel → process
array_push(_list, ["jmp_abs", _L_done, _id]); // sentinel → exit (far)
array_push(_list, ["label",   _L_body]);

// stamp-def ptr = STAMPDEF[stamp]  (X = stamp idx)
array_push(_list, ["tax",     0,    _id]);
array_push(_list, ["lda_abx", _vpfx + "stampdef_lo", _id]);
array_push(_list, ["sta_zp",  0x24, _id]);
array_push(_list, ["lda_abx", _vpfx + "stampdef_hi", _id]);
array_push(_list, ["sta_zp",  0x25, _id]);

// gx = list[1]  (Y=1) → screen column = gx * stamp_w
array_push(_list, ["iny",     0,    _id]); // Y = 1
array_push(_list, ["lda_izy", 0xFB, _id]); // A = gx
if (_sw == 1) {
    // gx already correct
} else if (_sw == 2) {
    array_push(_list, ["asl_a", 0, _id]);                 // gx*2
} else if (_sw == 4) {
    array_push(_list, ["asl_a", 0, _id]);
    array_push(_list, ["asl_a", 0, _id]);                 // gx*4
} else {
    array_push(_list, ["sta_zp", 0xFD, _id]);             // $FD = gx
    for (var _mw = 1; _mw < _sw; _mw++) {
        array_push(_list, ["clc",    0,    _id]);
        array_push(_list, ["adc_zp", 0xFD, _id]);         // A += gx
    }
}
array_push(_list, ["sta_zp",  0xFD, _id]); // stash gx*_sw (screen column)

// gy = list[2]  (Y=2) → screen row via ROWMUL
array_push(_list, ["iny",     0,    _id]); // Y = 2
array_push(_list, ["lda_izy", 0xFB, _id]); // A = gy

// ── advance the room-list base pointer by 3 (16-bit) for the next entry ──
// Done here while gy is safely in A; we restore A right after.
array_push(_list, ["pha",     0,    _id]); // save gy
array_push(_list, ["clc",     0,    _id]);
array_push(_list, ["lda_zp",  0xFB, _id]);
array_push(_list, ["adc_imm", 0x03, _id]);
array_push(_list, ["sta_zp",  0xFB, _id]);
array_push(_list, ["lda_zp",  0xFC, _id]);
array_push(_list, ["adc_imm", 0x00, _id]);
array_push(_list, ["sta_zp",  0xFC, _id]);
array_push(_list, ["pla",     0,    _id]); // restore gy into A

// screen row = ROWMUL[gy]   (gy in A -> X)
array_push(_list, ["tax",     0,    _id]);
array_push(_list, ["lda_abx", _vpfx + "rowmul", _id]); // A = gy*_sh
array_push(_list, ["tax",     0,    _id]);             // X = screen row 0..24

// screen base = COLL_ROW[X] (+ non-$0400 page adjust)
array_push(_list, ["lda_abx", "COLL_ROW_LO", _id]);
array_push(_list, ["sta_zp",  0xE3, _id]);
array_push(_list, ["lda_abx", "COLL_ROW_HI", _id]);
if (_v_scr != 0x0400) {
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_imm", ((_v_scr - 0x0400) >> 8) & 0xFF, _id]);
}
array_push(_list, ["sta_zp",  0xE4, _id]);

// colour base = same row, $D800 page
array_push(_list, ["lda_zp",  0xE3, _id]);
array_push(_list, ["sta_zp",  0x22, _id]);
array_push(_list, ["lda_zp",  0xE4, _id]);
array_push(_list, ["clc",     0,    _id]);
array_push(_list, ["adc_imm", ((0xD800 - _v_scr) >> 8) & 0xFF, _id]);
array_push(_list, ["sta_zp",  0x23, _id]);

// add gx to both column bases
array_push(_list, ["clc",     0,    _id]);
array_push(_list, ["lda_zp",  0xE3, _id]);
array_push(_list, ["adc_zp",  0xFD, _id]);
array_push(_list, ["sta_zp",  0xE3, _id]);
array_push(_list, ["lda_zp",  0xE4, _id]);
array_push(_list, ["adc_imm", 0x00, _id]);
array_push(_list, ["sta_zp",  0xE4, _id]);
array_push(_list, ["clc",     0,    _id]);
array_push(_list, ["lda_zp",  0x22, _id]);
array_push(_list, ["adc_zp",  0xFD, _id]);
array_push(_list, ["sta_zp",  0x22, _id]);
array_push(_list, ["lda_zp",  0x23, _id]);
array_push(_list, ["adc_imm", 0x00, _id]);
array_push(_list, ["sta_zp",  0x23, _id]);

// ── stamp the _sw x _sh cells (unrolled; _sw/_sh baked) ──
// Each cell-row is written with Y = column only (0.._sw-1), then the screen
// ($E3/$E4) and colour ($22/$23) base pointers advance by 40 to the next row.
// A flat Y = row*40 + col offset overflows the 8-bit Y register once row*40
// exceeds 255 (row 7 of an 8x8 metatile: 280 wraps to 24), which shifted the
// bottom row sideways. Advancing the pointer keeps Y small.
var _sdY = 0;
for (var _csy = 0; _csy < _sh; _csy++)
{
    for (var _csx = 0; _csx < _sw; _csx++)
    {
        // char cell -> screen
        array_push(_list, ["ldy_imm", _sdY,        _id]);
        array_push(_list, ["lda_izy", 0x24,        _id]);
        array_push(_list, ["ldy_imm", _csx & 0xFF, _id]);
        array_push(_list, ["sta_izy", 0xE3,        _id]);
        // colour cell -> colour RAM
        array_push(_list, ["ldy_imm", _sdY + 1,    _id]);
        array_push(_list, ["lda_izy", 0x24,        _id]);
        array_push(_list, ["ldy_imm", _csx & 0xFF, _id]);
        array_push(_list, ["sta_izy", 0x22,        _id]);
        _sdY += 2;
    }

    // Advance screen + colour bases by 40 to the next cell-row, unless this
    // was the last row (avoids a pointless final add).
    var _is_last_row = (_csy == (_sh - 1));
    if (_is_last_row == false)
    {
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xE3, _id]);
        array_push(_list, ["adc_imm", 40,   _id]);
        array_push(_list, ["sta_zp",  0xE3, _id]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["adc_imm", 0,    _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);

        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0x22, _id]);
        array_push(_list, ["adc_imm", 40,   _id]);
        array_push(_list, ["sta_zp",  0x22, _id]);
        array_push(_list, ["lda_zp",  0x23, _id]);
        array_push(_list, ["adc_imm", 0,    _id]);
        array_push(_list, ["sta_zp",  0x23, _id]);
    }
}

// next placement — base pointer already advanced; just loop (Y reset at _L_next)
array_push(_list, ["jmp_abs", _L_next, _id]);

array_push(_list, ["label", _L_done]);

// ── Restore the 8 sprite pointers, undoing any stamp overspill ──
array_push(_list, ["ldx_imm", 0x00,             _id]);
array_push(_list, ["label",   _vpfx + "sprs"]);
array_push(_list, ["lda_abx", _vpfx + "spsave", _id]);
array_push(_list, ["sta_abx", _v_sptr,          _id]);
array_push(_list, ["inx",     0,                _id]);
array_push(_list, ["cpx_imm", 0x08,             _id]);
array_push(_list, ["bne",     _vpfx + "sprs",   _id]);

array_push(_list, ["cli", 0, _id]);


        // ── COLL_ADV types table (shared with LIT path) ──
        var _v_types = undefined;
        if (variable_struct_exists(_tm, "chr_asset") && _tm.chr_asset != "" && instance_exists(obj_asset_manager)) {
            var _vamc = obj_asset_manager;
            for (var _vci = 0; _vci < ds_list_size(_vamc.asset_list); _vci++) {
                var _vca = ds_list_find_value(_vamc.asset_list, _vci);
                if (_vca.type == "CHAR_SET" && _vca.name == _tm.chr_asset) {
                    if (variable_struct_exists(_vca.meta, "tile_types") && is_array(_vca.meta.tile_types))
                        _v_types = _vca.meta.tile_types;
                    break;
                }
            }
        }
        var _v_has_types = false;
        if (is_array(_v_types)) {
            for (var _vtti = 0; _vtti < array_length(_v_types); _vtti++) {
                if (_v_types[_vtti] != 0) { _v_has_types = true; break; }
            }
        }
        if (_v_has_types) {
            var _v_tbl_skip = _vpfx + "ttskip";
            array_push(_list, ["jmp_abs", _v_tbl_skip, _id]);
            array_push(_list, ["label", string(_tileset_name) + "_TILE_TYPES"]);
            for (var _vtti = 0; _vtti < array_length(_v_types); _vtti++) {
                if (_v_types[_vtti] != 0) {
                    array_push(_list, ["byte", _vtti & 0xFF,                 _id]);
                    array_push(_list, ["byte", real(_v_types[_vtti]) & 0xFF, _id]);
                }
            }
            array_push(_list, ["byte", 0xFF, _id]);
            array_push(_list, ["label", _v_tbl_skip]);
        }

        break; // VAR mode complete — skip the LIT emit below
    }

    var _char_src = _base_addr;
    var _col_src  = _base_addr + 1000;

    // DEBUG: verify the plane actually got populated
    var _mm_nonzero = 0;
    for (var _dbi = 0; _dbi < 1000; _dbi++) {
        if (_char_plane[_dbi] != 0) _mm_nonzero++;
    }
    show_debug_message("METAMAP LIT: grid_len=" + string(array_length(_grid))
        + " cols=" + string(_cols) + " rows=" + string(_rows)
        + " sw=" + string(_sw) + " sh=" + string(_sh)
        + " stamp_count=" + string(_tm.stamp_count)
        + " char_plane nonzero=" + string(_mm_nonzero)
        + " char_src=$" + string_upper(decimal_to_hex(_char_src)));

    // ── Emit both planes at base_addr via PC save/restore ──
    // org -2 = save current spine PC, jump; org -3 = restore it afterwards.
    var _mm_pfx = "mmm_" + string(real(_id)) + "_";
    array_push(_list, ["org", -2]);
    array_push(_list, ["org", _char_src]);
    array_push(_list, ["label", _mm_pfx + "chardata"]);
    var _mm_id_save = _id;
    var _id = noone; // suppress node tagging on raw plane data
    for (var _bi = 0; _bi < 1000; _bi++) array_push(_list, ["byte", _char_plane[_bi]]);
    for (var _bi = 0; _bi < 1000; _bi++) array_push(_list, ["byte", _col_plane[_bi]]);
    array_push(_list, ["org", -3]); // restore spine PC
    var _id = _mm_id_save;

    // ── Resolve screen destination from MACRO_VIC (same as MACRO_MAP) ──
    var _scr_dest = 0x0400;
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && org_parent == noone) {
            if (array_length(instructions[0]) > 3 && is_real(instructions[0][3]))
                _scr_dest = real(instructions[0][3]);
            break;
        }
    }

    var _scr_w = 40;
    var _scr_h = 25;
    var _lbl_chr_row = _mm_pfx + "cr";
    var _lbl_chr_inn = _mm_pfx + "ci";
    var _lbl_col_row = _mm_pfx + "lr";
    var _lbl_col_inn = _mm_pfx + "li";

    // ── VIC background colours: ECM (4 registers) or MC (mixed mode) ──
    if (_mm_is_ecm) {
        var _l_ecm_bg0 = variable_struct_exists(_mm_chr_ref.meta, "mc_bg")   ? _mm_chr_ref.meta.mc_bg   : 0;
        var _l_ecm_bg1 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg1") ? _mm_chr_ref.meta.ecm_bg1 : 6;
        var _l_ecm_bg2 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg2") ? _mm_chr_ref.meta.ecm_bg2 : 14;
        var _l_ecm_bg3 = variable_struct_exists(_mm_chr_ref.meta, "ecm_bg3") ? _mm_chr_ref.meta.ecm_bg3 : 3;
        array_push(_list, ["lda_imm", _l_ecm_bg0, _id]);
        array_push(_list, ["sta_abs", 0xD021,     _id]);
        array_push(_list, ["lda_imm", _l_ecm_bg1, _id]);
        array_push(_list, ["sta_abs", 0xD022,     _id]);
        array_push(_list, ["lda_imm", _l_ecm_bg2, _id]);
        array_push(_list, ["sta_abs", 0xD023,     _id]);
        array_push(_list, ["lda_imm", _l_ecm_bg3, _id]);
        array_push(_list, ["sta_abs", 0xD024,     _id]);
    } else if (_mm_mode == 1) {
        var _mc_bg   = (variable_struct_exists(_tm, "map_mc_bg")   && _tm.map_mc_bg   >= 0) ? _tm.map_mc_bg   : 0;
        var _mc_col1 = (variable_struct_exists(_tm, "map_mc_col1") && _tm.map_mc_col1 >= 0) ? _tm.map_mc_col1 : 1;
        var _mc_col2 = (variable_struct_exists(_tm, "map_mc_col2") && _tm.map_mc_col2 >= 0) ? _tm.map_mc_col2 : 2;
        array_push(_list, ["lda_imm", _mc_bg,   _id]);
        array_push(_list, ["sta_abs", 0xD021,   _id]);
        array_push(_list, ["lda_imm", _mc_col1, _id]);
        array_push(_list, ["sta_abs", 0xD022,   _id]);
        array_push(_list, ["lda_imm", _mc_col2, _id]);
        array_push(_list, ["sta_abs", 0xD023,   _id]);
        // Enable VIC-II multicolour text mode (set $D016 bit 4)
        array_push(_list, ["lda_abs", 0xD016, _id]);
        array_push(_list, ["ora_imm", 0x10,   _id]);
        array_push(_list, ["sta_abs", 0xD016, _id]);
    }

    // ── CHAR COPY: _char_src -> _scr_dest, 25 rows of 40 (IRQ-safe) ──
    array_push(_list, ["sei", 0, _id]);
    array_push(_list, ["lda_imm", _char_src & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xFB,                    _id]);
    array_push(_list, ["lda_imm", (_char_src >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xFC,                    _id]);
    array_push(_list, ["lda_imm", _scr_dest & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xE3,                    _id]);
    array_push(_list, ["lda_imm", (_scr_dest >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xE4,                    _id]);
    array_push(_list, ["ldx_imm", _scr_h,                  _id]);
    array_push(_list, ["label",   _lbl_chr_row]);
    array_push(_list, ["ldy_imm", 0,                       _id]);
    array_push(_list, ["label",   _lbl_chr_inn]);
    array_push(_list, ["lda_izy", 0xFB,                    _id]);
    array_push(_list, ["sta_izy", 0xE3,                    _id]);
    array_push(_list, ["iny",     0,                       _id]);
    array_push(_list, ["cpy_imm", _scr_w,                  _id]);
    array_push(_list, ["bne",     _lbl_chr_inn,            _id]);
    array_push(_list, ["lda_zp",  0xFB,                    _id]);
    array_push(_list, ["clc",     0,                       _id]);
    array_push(_list, ["adc_imm", _scr_w,                  _id]);
    array_push(_list, ["sta_zp",  0xFB,                    _id]);
    array_push(_list, ["lda_zp",  0xFC,                    _id]);
    array_push(_list, ["adc_imm", 0,                       _id]);
    array_push(_list, ["sta_zp",  0xFC,                    _id]);
    array_push(_list, ["lda_zp",  0xE3,                    _id]);
    array_push(_list, ["clc",     0,                       _id]);
    array_push(_list, ["adc_imm", _scr_w,                  _id]);
    array_push(_list, ["sta_zp",  0xE3,                    _id]);
    array_push(_list, ["lda_zp",  0xE4,                    _id]);
    array_push(_list, ["adc_imm", 0,                       _id]);
    array_push(_list, ["sta_zp",  0xE4,                    _id]);
    array_push(_list, ["dex",     0,                       _id]);
    array_push(_list, ["bne",     _lbl_chr_row,            _id]);

    // ── COLOUR COPY: _col_src (+col_row_start rows) -> $D800 (+offset) ──
    var _col_dest    = 0xD800 + (_col_row_start * 40);
    var _col_src_off = _col_src + (_col_row_start * 40);
    array_push(_list, ["lda_imm", _col_src_off & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xFB,                       _id]);
    array_push(_list, ["lda_imm", (_col_src_off >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xFC,                       _id]);
    array_push(_list, ["lda_imm", _col_dest & 0xFF,           _id]);
    array_push(_list, ["sta_zp",  0xE3,                       _id]);
    array_push(_list, ["lda_imm", (_col_dest >> 8) & 0xFF,    _id]);
    array_push(_list, ["sta_zp",  0xE4,                       _id]);
    array_push(_list, ["ldx_imm", _scr_h - _col_row_start,    _id]);
    array_push(_list, ["label",   _lbl_col_row]);
    array_push(_list, ["ldy_imm", 0,                          _id]);
    array_push(_list, ["label",   _lbl_col_inn]);
    array_push(_list, ["lda_izy", 0xFB,                       _id]);
    array_push(_list, ["sta_izy", 0xE3,                       _id]);
    array_push(_list, ["iny",     0,                          _id]);
    array_push(_list, ["cpy_imm", _scr_w,                     _id]);
    array_push(_list, ["bne",     _lbl_col_inn,               _id]);
    array_push(_list, ["lda_zp",  0xFB,                       _id]);
    array_push(_list, ["clc",     0,                          _id]);
    array_push(_list, ["adc_imm", _scr_w,                     _id]);
    array_push(_list, ["sta_zp",  0xFB,                       _id]);
    array_push(_list, ["lda_zp",  0xFC,                       _id]);
    array_push(_list, ["adc_imm", 0,                          _id]);
    array_push(_list, ["sta_zp",  0xFC,                       _id]);
    array_push(_list, ["lda_zp",  0xE3,                       _id]);
    array_push(_list, ["clc",     0,                          _id]);
    array_push(_list, ["adc_imm", _scr_w,                     _id]);
    array_push(_list, ["sta_zp",  0xE3,                       _id]);
    array_push(_list, ["lda_zp",  0xE4,                       _id]);
    array_push(_list, ["adc_imm", 0,                          _id]);
    array_push(_list, ["sta_zp",  0xE4,                       _id]);
    array_push(_list, ["dex",     0,                          _id]);
    array_push(_list, ["bne",     _lbl_col_row,               _id]);
    array_push(_list, ["cli",     0,                          _id]);

    // ── COLL_ADV: <tileset>_TILE_TYPES sourced from tileset's chr_asset ──
    var _mm_types = undefined;
    if (variable_struct_exists(_tm, "chr_asset") && _tm.chr_asset != "" && instance_exists(obj_asset_manager)) {
        var _amc = obj_asset_manager;
        for (var _ci = 0; _ci < ds_list_size(_amc.asset_list); _ci++) {
            var _ca = ds_list_find_value(_amc.asset_list, _ci);
            if (_ca.type == "CHAR_SET" && _ca.name == _tm.chr_asset) {
                if (variable_struct_exists(_ca.meta, "tile_types") && is_array(_ca.meta.tile_types))
                    _mm_types = _ca.meta.tile_types;
                break;
            }
        }
    }
    var _mm_has_types = false;
    if (is_array(_mm_types)) {
        for (var _tti = 0; _tti < array_length(_mm_types); _tti++) {
            if (_mm_types[_tti] != 0) { _mm_has_types = true; break; }
        }
    }
    if (_mm_has_types) {
        // Table lives in code space, on the spine — COLL_ADV scans it by label.
        var _mm_tbl_skip = _mm_pfx + "ttskip";
        array_push(_list, ["jmp_abs", _mm_tbl_skip, _id]);
        array_push(_list, ["label", string(_tileset_name) + "_TILE_TYPES"]);
        // NOTE: tag every byte with _id so Pass 1.5 (scr_c64_do_update_addresses)
        // counts them into total_node_size. These bytes live INLINE on the spine
        // (jumped over at runtime), so the node PC MUST include them — unlike the
        // org-bracketed plane data above, which is restored via org -3.
        for (var _tti = 0; _tti < array_length(_mm_types); _tti++) {
            if (_mm_types[_tti] != 0) {
                array_push(_list, ["byte", _tti & 0xFF,                  _id]);
                array_push(_list, ["byte", real(_mm_types[_tti]) & 0xFF, _id]);
            }
        }
        array_push(_list, ["byte", 0xFF, _id]); // sentinel
        // Global row LUTs — emit once, first map wins (shared with MAP_DATA path)
        if (!variable_global_exists("coll_row_luts_emitted") || global.coll_row_luts_emitted == false) {
            array_push(_list, ["label", "COLL_ROW_LO"]);
            var _row_lo = [0x00,0x28,0x50,0x78,0xA0,0xC8,0xF0,0x18,0x40,0x68,0x90,0xB8,0xE0,0x08,0x30,0x58,0x80,0xA8,0xD0,0xF8,0x20,0x48,0x70,0x98,0xC0];
            for (var _ri = 0; _ri < 25; _ri++) array_push(_list, ["byte", _row_lo[_ri], _id]);
            array_push(_list, ["label", "COLL_ROW_HI"]);
            var _row_hi = [0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x05,0x05,0x05,0x05,0x05,0x05,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x07,0x07,0x07,0x07,0x07];
            for (var _ri = 0; _ri < 25; _ri++) array_push(_list, ["byte", _row_hi[_ri], _id]);
            global.coll_row_luts_emitted = true;
        }
        array_push(_list, ["label", _mm_tbl_skip]);
    }

} break;


case "MACRO_MAP_SWITCH": {
    var _id         = _curr;
    var _asset_name = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";

    if (_asset_name == "") { break; }

    // Find MACRO_MAP node in chain to get ZP base
    var _zp_base = -1;
    with (obj_c64_node) {
        if (node_type == "MACRO_MAP" && is_connected) {
            if (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) {
                _zp_base = real(instructions[0][6]);
            } else {
                _zp_base = 0x50;
            }
            break;
        }
    }

    // No MACRO_MAP found — silent no-op
    if (_zp_base == -1) { break; }

    var _zp_src_lo = _zp_base;
    var _zp_src_hi = _zp_base + 1;
    var _zp_col_lo = _zp_base + 2;
    var _zp_col_hi = _zp_base + 3;

    // Resolve MAP_DATA asset
    var _map_w    = 40;
    var _map_h    = 25;
    var _char_src = 0x8000;
    var _col_src  = 0x8000 + (_map_w * _map_h);
    var _mc_bg    = 0;
    var _mc_col1  = 1;
    var _mc_col2  = 2;
    var _map_mode = obj_workspace_manager.map_global_mixed;

    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                _char_src = _a.address;
                if (variable_struct_exists(_a.meta, "map_w")) { _map_w = _a.meta.map_w; }
                if (variable_struct_exists(_a.meta, "map_h")) { _map_h = _a.meta.map_h; }
                _col_src = _char_src + (_map_w * _map_h);
                if (_map_mode == 1) {
                    if (variable_struct_exists(_a.meta, "map_mc_bg"))   { _mc_bg   = _a.meta.map_mc_bg;   }
                    if (variable_struct_exists(_a.meta, "map_mc_col1")) { _mc_col1 = _a.meta.map_mc_col1; }
                    if (variable_struct_exists(_a.meta, "map_mc_col2")) { _mc_col2 = _a.meta.map_mc_col2; }
                    // Fall back to linked charset if map has no override
                    if (variable_struct_exists(_a.meta, "chr_asset") && _a.meta.chr_asset != "") {
                        var _chr_nm = _a.meta.chr_asset;
                        for (var _ci = 0; _ci < ds_list_size(_am.asset_list); _ci++) {
                            var _ca = ds_list_find_value(_am.asset_list, _ci);
                            if (_ca.type == "CHAR_SET" && _ca.name == _chr_nm) {
                                if (_mc_bg   == 0 && variable_struct_exists(_ca.meta, "mc_bg"))   { _mc_bg   = _ca.meta.mc_bg;   }
                                if (_mc_col1 == 1 && variable_struct_exists(_ca.meta, "mc_col1")) { _mc_col1 = _ca.meta.mc_col1; }
                                if (_mc_col2 == 2 && variable_struct_exists(_ca.meta, "mc_col2")) { _mc_col2 = _ca.meta.mc_col2; }
                                break;
                            }
                        }
                    }
                }
                break;
            }
        }
    }

    // Write char source address into ZP pointer pair
    array_push(_list, ["lda_imm", _char_src & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  _zp_src_lo,              _id]);
    array_push(_list, ["lda_imm", (_char_src >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  _zp_src_hi,              _id]);
    // Write colour source address into ZP pointer pair
    array_push(_list, ["lda_imm", _col_src & 0xFF,         _id]);
    array_push(_list, ["sta_zp",  _zp_col_lo,              _id]);
    array_push(_list, ["lda_imm", (_col_src >> 8) & 0xFF,  _id]);
    array_push(_list, ["sta_zp",  _zp_col_hi,              _id]);

    // Write MC colours if in mixed mode
    if (_map_mode == 1) {
        array_push(_list, ["lda_imm", _mc_bg,   _id]);
        array_push(_list, ["sta_abs", 0xD021,    _id]);
        array_push(_list, ["lda_imm", _mc_col1,  _id]);
        array_push(_list, ["sta_abs", 0xD022,    _id]);
        array_push(_list, ["lda_imm", _mc_col2,  _id]);
        array_push(_list, ["sta_abs", 0xD023,    _id]);
    }

    // Reset scroll ZP to zero
    array_push(_list, ["lda_imm", 0x00,   _id]);
    array_push(_list, ["sta_zp",  0xF7,   _id]); // scroll_x lo
    array_push(_list, ["sta_zp",  0xF8,   _id]); // scroll_x hi
    array_push(_list, ["sta_zp",  0xF9,   _id]); // scroll_y

    // Call shared redraw routine
    array_push(_list, ["jsr",     "map_redraw", _id]);

} break;
	

// --------------------------------------------------------
// MACRO_SCROLL (HORIZONTAL MAP H SCROLL) — unified delta core
// scroll_fine (0-7) + scrollx (column) are the single source of truth.
// $D016 is WRITTEN from scroll_fine, never read back to make decisions.
// Scroller_L / Scroller_R just set the direction sign and fall into the core.
// --------------------------------------------------------
case "MACRO_SCROLL": {

    var _id  = _curr;
    if (!variable_instance_exists(_id, "scroll_alias") || _id.scroll_alias == "")
        _id.scroll_alias = "scr" + string(real(_id));
    var _p   = _id.scroll_alias + "_";
    // Entry points are Scroller_L and Scroller_R — emitted as labels below

    var _col_mode  = (array_length(_id.instructions[0]) > 3 && is_real(_id.instructions[0][3])) ? real(_id.instructions[0][3]) : 1;

    // Resolve HR/Mixed from global workspace flag — single source of truth
    var _scroll_map_mode = obj_workspace_manager.map_global_mixed;
    // bits 7-4 of $D016 we always want set: $C0, plus the mode bit in bit 4
    var _ctrl_bits = 0xC0 | (_scroll_map_mode << 4);

    var _start_row = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) ? clamp(real(_id.instructions[0][1]), 0, 24) : 0;
    var _has_sid_scroll = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _has_sid_scroll = true; break; }
    }
    var _max_rows  = 25 - _start_row;
    var _row_count = (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2])) ? clamp(real(_id.instructions[0][2]), 1, _max_rows) : _max_rows;

    // Resolve MAP_DATA asset
    // Priority: MACRO_MAP_SWITCH (last on spine) > MACRO_MAP (last on spine) > first asset
    var _map_w    = 40;
    var _map_h    = 25;
    var _map_base = 0x8000;
    var _scroll_map_name = "";
    // Use MACRO_MAP_SWITCH if present, otherwise MACRO_MAP — just needs to be connected
    with (obj_c64_node) {
        if (node_type == "MACRO_MAP_SWITCH" && is_connected) {
            if (array_length(instructions[0]) > 1) {
                _scroll_map_name = string(instructions[0][1]);
                break;
            }
        }
    }
    if (_scroll_map_name == "") {
        with (obj_c64_node) {
            if (node_type == "MACRO_MAP" && is_connected) {
                if (array_length(instructions[0]) > 1) {
                    _scroll_map_name = string(instructions[0][1]);
                    break;
                }
            }
        }
    }
    if (instance_exists(obj_asset_manager) && _scroll_map_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA" && _a.name == _scroll_map_name) {
                _map_base = _a.address;
                if (variable_struct_exists(_a, "meta")) {
                    if (variable_struct_exists(_a.meta, "map_w")) _map_w = _a.meta.map_w;
                    if (variable_struct_exists(_a.meta, "map_h")) _map_h = _a.meta.map_h;
                }
                break;
            }
        }
    } else if (instance_exists(obj_asset_manager)) {
        // Last resort fallback: first MAP_DATA asset in list
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA") {
                _map_base = _a.address;
                if (variable_struct_exists(_a, "meta")) {
                    if (variable_struct_exists(_a.meta, "map_w")) _map_w = _a.meta.map_w;
                    if (variable_struct_exists(_a.meta, "map_h")) _map_h = _a.meta.map_h;
                }
                break;
            }
        }
    }

    var _msz   = _map_w * _map_h;

    // Resolve screen RAM base from MACRO_VIC node — fall back to $0400 if not found
    var _scr1 = 0x0400;
    var _vic_bank_scroll = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && is_connected && org_parent == noone) {
            var _vic_mode_scroll = string(instructions[0][1]);
            if (_vic_mode_scroll == "BITMAP" || _vic_mode_scroll == "BMP" || _vic_mode_scroll == "MCB") {
                var _chr_s = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0x4000;
                _scr1 = _chr_s + 0x2000;
            } else {
                _scr1 = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
            }
            _vic_bank_scroll = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
            break;
        }
    }
    var _scr2  = _scr1 + 0x0800;
    var _cam_w = 39;

    // ── Labels ────────────────────────────────────────────────
    var _lbl_scrollx      = _p + "scrollx";    // current leftmost map column
    var _lbl_fine         = _p + "fine";       // fine scroll 0-7
    var _lbl_dir          = _p + "dir";        // direction: $00 = right/up, $FF = left/down
    var _lbl_skip_var     = _p + "skipvar";
    var _lbl_init         = _p + "init";
    var _lbl_after_init   = _p + "afterinit";
    var _lbl_core         = _p + "core";       // shared update routine
    var _lbl_dir_down     = _p + "dirdown";
    var _lbl_no_wrap_hi   = _p + "nowraphi";
    var _lbl_no_wrap_lo   = _p + "nowraplo";
    var _lbl_did_load     = _p + "didload";
    var _lbl_load_use2    = _p + "loaduse2";
    var _lbl_load_done    = _p + "loaddone";
    var _lbl_colcheck     = _p + "colcheck";   // wrap scrollx hi side
    var _lbl_col_nowrap_r = _p + "colnowrapr";
    var _lbl_col_nowrap_l = _p + "colnowrapl";
    // $D018 flip
    var _lbl_use_scr2     = _p + "use2";
    var _lbl_scr_set      = _p + "scrset";
    // screen-1 / screen-2 / colour loaders
    var _lbl_scr1         = _p + "scr1";
    var _lbl_scr1_cols    = _p + "scr1cols";
    var _lbl_scr1_done    = _p + "scr1done";
    var _lbl_scr1_nowrap  = _p + "scr1nowrap";
    var _lbl_scr2         = _p + "scr2";
    var _lbl_scr2_cols    = _p + "scr2cols";
    var _lbl_scr2_done    = _p + "scr2done";
    var _lbl_scr2_nowrap  = _p + "scr2nowrap";
    var _lbl_color        = _p + "color";
    var _lbl_color_cols   = _p + "colcols";
    var _lbl_color_done   = _p + "coldone";
    var _lbl_color_nowrap = _p + "colnowrap";
    var _lbl_zero1        = _p + "zero1";
    var _lbl_zero2        = _p + "zero2";
    var _lbl_zero3        = _p + "zero3";
    var _lbl_zero4        = _p + "zero4";
    var _lbl_spr_init     = _p + "sprinit";

    // ── RAM variables (3 bytes), jumped over ─────────────────
    array_push(_list, ["jmp_abs", _lbl_skip_var,   _id]);
    array_push(_list, ["label",   _lbl_scrollx]);
    array_push(_list, ["byte",    0x00,             _id]);
    array_push(_list, ["label",   _lbl_fine]);
    array_push(_list, ["byte",    0x07,             _id]);   // seeded to 7 to match init's $D016 = $07
    array_push(_list, ["label",   _lbl_dir]);
    array_push(_list, ["byte",    0x00,             _id]);
    array_push(_list, ["label",   _lbl_skip_var]);

    // ── Call init then JMP over all subroutines ───────────────
    array_push(_list, ["jsr",     _lbl_init,        _id]);
    array_push(_list, ["jmp_abs", _lbl_after_init,  _id]);

    // ════════════════════════════════════════════════════════
    // Scroller_L — JSR each frame to scroll left (camera pans right)
    // Sets dir = $FF (walk fine DOWN), falls into core.
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   "Scroller_L"]);
    array_push(_list, ["lda_imm", 0xFF,             _id]);
    array_push(_list, ["sta_lab", _lbl_dir,         _id]);
    array_push(_list, ["jmp_abs", _lbl_core,        _id]);

    // ════════════════════════════════════════════════════════
    // Scroller_R — JSR each frame to scroll right (camera pans left)
    // Sets dir = $00 (walk fine UP), falls into core.
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   "Scroller_R"]);
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["sta_lab", _lbl_dir,         _id]);
    // falls through into core

    // ════════════════════════════════════════════════════════
    // Core update — the single source of truth.
    //   dir == $FF : fine -= 1 ; on underflow (fine<0) wrap to 7,
    //                advance column LEFT, load new column.
    //   dir == $00 : fine += 1 ; on overflow (fine>7) wrap to 0,
    //                advance column RIGHT, load new column.
    //   Always: write (fine | ctrl_bits) to $D016, flip $D018 by col parity.
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_core]);

    array_push(_list, ["lda_lab", _lbl_dir,         _id]);
    array_push(_list, ["bne",     _lbl_dir_down,    _id]);   // $FF -> down branch

    // ---- dir == $00 : scroll RIGHT, fine DOWN (D016 is a delay, counts opposite to travel) ----
    array_push(_list, ["lda_lab", _lbl_fine,        _id]);
    array_push(_list, ["sec",     0,                _id]);
    array_push(_list, ["sbc_imm", 0x01,             _id]);
    array_push(_list, ["bpl",     _lbl_no_wrap_hi,  _id]);   // fine >= 0 -> no wrap
    // wrap: fine = 7, advance column to the RIGHT, load
    array_push(_list, ["lda_imm", 0x07,             _id]);
    array_push(_list, ["sta_lab", _lbl_fine,        _id]);
    // scrollx = (scrollx + 1) mod map_w
    array_push(_list, ["lda_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["clc",     0,                _id]);
    array_push(_list, ["adc_imm", 0x01,             _id]);
    array_push(_list, ["cmp_imm", _map_w & 0xFF,    _id]);
    array_push(_list, ["bcc",     _lbl_col_nowrap_r,_id]);
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_col_nowrap_r]);
    array_push(_list, ["sta_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["jmp_abs", _lbl_did_load,    _id]);
    array_push(_list, ["label",   _lbl_no_wrap_hi]);
    array_push(_list, ["sta_lab", _lbl_fine,        _id]);
    array_push(_list, ["jmp_abs", _lbl_load_done,   _id]); // no column load this frame

    // ---- dir == $FF : scroll LEFT, fine UP (D016 is a delay, counts opposite to travel) ----
    array_push(_list, ["label",   _lbl_dir_down]);
    array_push(_list, ["lda_lab", _lbl_fine,        _id]);
    array_push(_list, ["clc",     0,                _id]);
    array_push(_list, ["adc_imm", 0x01,             _id]);
    array_push(_list, ["cmp_imm", 0x08,             _id]);
    array_push(_list, ["bcc",     _lbl_no_wrap_lo,  _id]);   // fine < 8 -> no wrap
    // overflow: fine = 0, advance column to the LEFT, load
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["sta_lab", _lbl_fine,        _id]);
    // scrollx = (scrollx - 1) mod map_w  (0 -> map_w-1)
    array_push(_list, ["lda_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["bne",     _lbl_col_nowrap_l,_id]);
    array_push(_list, ["lda_imm", _map_w & 0xFF,    _id]);
    array_push(_list, ["label",   _lbl_col_nowrap_l]);
    array_push(_list, ["sec",     0,                _id]);
    array_push(_list, ["sbc_imm", 0x01,             _id]);
    array_push(_list, ["sta_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["jmp_abs", _lbl_did_load,    _id]);
    array_push(_list, ["label",   _lbl_no_wrap_lo]);
    array_push(_list, ["sta_lab", _lbl_fine,        _id]);
    array_push(_list, ["jmp_abs", _lbl_load_done,   _id]); // no column load this frame

    // ---- a column boundary was crossed: load into the off-buffer ----
    array_push(_list, ["label",   _lbl_did_load]);
    array_push(_list, ["lda_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["and_imm", 0x01,             _id]);
    array_push(_list, ["bne",     _lbl_load_use2,   _id]);
    array_push(_list, ["jsr",     _lbl_scr1,        _id]);
    array_push(_list, ["jmp_abs", _lbl_load_done,   _id]);
    array_push(_list, ["label",   _lbl_load_use2]);
    array_push(_list, ["jsr",     _lbl_scr2,        _id]);
    array_push(_list, ["label",   _lbl_load_done]);

    // ---- write fine scroll to $D016 (unconditional) ----
    array_push(_list, ["lda_lab", _lbl_fine,        _id]);
    array_push(_list, ["ora_imm", _ctrl_bits,       _id]);
    array_push(_list, ["sta_abs", 0xD016,           _id]);

    // ---- $D018 buffer flip from scrollx parity ----
    array_push(_list, ["lda_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["and_imm", 0x01,             _id]);
    array_push(_list, ["bne",     _lbl_use_scr2,    _id]);
    var _bank_base_scroll = _vic_bank_scroll * 0x4000;
    var _d018_scr1 = (floor((_scr1 - _bank_base_scroll) / 0x0400) & 0x0F) << 4;
    var _d018_scr2 = (floor((_scr2 - _bank_base_scroll) / 0x0400) & 0x0F) << 4;
    // Preserve charset/bitmap bits from existing $D018 (bits 0-3), only replace screen nibble (bits 4-7)
    array_push(_list, ["lda_abs", 0xD018,           _id]);
    array_push(_list, ["and_imm", 0x0F,             _id]);
    array_push(_list, ["ora_imm", _d018_scr1,       _id]);
    array_push(_list, ["jmp_abs", _lbl_scr_set,     _id]);
    array_push(_list, ["label",   _lbl_use_scr2]);
    array_push(_list, ["lda_abs", 0xD018,           _id]);
    array_push(_list, ["and_imm", 0x0F,             _id]);
    array_push(_list, ["ora_imm", _d018_scr2,       _id]);
    array_push(_list, ["label",   _lbl_scr_set]);
    array_push(_list, ["sta_abs", 0xD018,           _id]);

    if (_col_mode != 0) {
        array_push(_list, ["jsr", _lbl_color,       _id]);
    }
    array_push(_list, ["rts",     0,                _id]);

    // ════════════════════════════════════════════════════════
    // Init subroutine
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_init]);
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["sta_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["lda_imm", 0x07,             _id]);
    array_push(_list, ["sta_lab", _lbl_fine,        _id]);
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["sta_lab", _lbl_dir,         _id]);

    array_push(_list, ["lda_abs", 0xD016,           _id]);
    array_push(_list, ["and_imm", 0xF0,             _id]);
    array_push(_list, ["ora_imm", 0x07 | (_scroll_map_mode << 4), _id]);
    array_push(_list, ["sta_abs", 0xD016,           _id]);
    array_push(_list, ["lda_abs", 0xD018,           _id]);
    array_push(_list, ["and_imm", 0x0F,             _id]);
    array_push(_list, ["ora_imm", _d018_scr1,       _id]);
    array_push(_list, ["sta_abs", 0xD018,           _id]);

    // Zero both screen buffers (1000 bytes each)
    array_push(_list, ["lda_imm", 0x00,             _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_zero1]);
    array_push(_list, ["sta_abx", _scr1,            _id]);
    array_push(_list, ["sta_abx", _scr2,            _id]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["bne",     _lbl_zero1,       _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_zero2]);
    array_push(_list, ["sta_abx", _scr1 + 0x100,   _id]);
    array_push(_list, ["sta_abx", _scr2 + 0x100,   _id]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["bne",     _lbl_zero2,       _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_zero3]);
    array_push(_list, ["sta_abx", _scr1 + 0x200,   _id]);
    array_push(_list, ["sta_abx", _scr2 + 0x200,   _id]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["bne",     _lbl_zero3,       _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_zero4]);
    array_push(_list, ["sta_abx", _scr1 + 0x300,   _id]);
    array_push(_list, ["sta_abx", _scr2 + 0x300,   _id]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["cpx_imm", 0xE8,             _id]);   // 232 bytes = 1000 - 768
    array_push(_list, ["bne",     _lbl_zero4,       _id]);

    // Load scrolled rows into both buffers
    array_push(_list, ["jsr",     _lbl_scr1,        _id]);
    array_push(_list, ["jsr",     _lbl_scr2,        _id]);
    // Copy sprite pointers scr1->scr2 so sprites don't glitch on first flip
    array_push(_list, ["ldx_imm", 0x07,             _id]);
    array_push(_list, ["label",   _lbl_spr_init]);
    array_push(_list, ["lda_abx", _scr1 + 0x3F8,   _id]);
    array_push(_list, ["sta_abx", _scr2 + 0x3F8,   _id]);
    array_push(_list, ["dex",     0,                _id]);
    array_push(_list, ["bpl",     _lbl_spr_init,    _id]);
    if (_col_mode != 0) {
        array_push(_list, ["jsr", _lbl_color,       _id]);
    }
    array_push(_list, ["rts",     0,                _id]);

    // ════════════════════════════════════════════════════════
    // loadMap_screen_1 — _row_count rows from _start_row into $0400
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_scr1]);
    array_push(_list, ["ldy_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_scr1_cols]);
    for (var _r = 0; _r < _row_count; _r++) {
        array_push(_list, ["lda_aby", _map_base + ((_r + _start_row) * _map_w), _id]);
        array_push(_list, ["sta_abx", _scr1     + ((_r + _start_row) * 40),     _id]);
    }
    array_push(_list, ["iny",     0,                _id]);
    array_push(_list, ["cpy_imm", _map_w & 0xFF,    _id]);
    array_push(_list, ["bcc",     _lbl_scr1_nowrap, _id]);
    array_push(_list, ["ldy_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_scr1_nowrap]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["cpx_imm", _cam_w,           _id]);
    array_push(_list, ["beq",     _lbl_scr1_done,   _id]);
    array_push(_list, ["jmp_abs", _lbl_scr1_cols,   _id]);
    array_push(_list, ["label",   _lbl_scr1_done]);
    array_push(_list, ["rts",     0,                _id]);

    // ════════════════════════════════════════════════════════
    // loadMap_screen_2 — _row_count rows from _start_row into $0C00
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_scr2]);
    array_push(_list, ["ldy_lab", _lbl_scrollx,     _id]);
    array_push(_list, ["ldx_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_scr2_cols]);
    for (var _r = 0; _r < _row_count; _r++) {
        array_push(_list, ["lda_aby", _map_base + ((_r + _start_row) * _map_w), _id]);
        array_push(_list, ["sta_abx", _scr2     + ((_r + _start_row) * 40),     _id]);
    }
    array_push(_list, ["iny",     0,                _id]);
    array_push(_list, ["cpy_imm", _map_w & 0xFF,    _id]);
    array_push(_list, ["bcc",     _lbl_scr2_nowrap, _id]);
    array_push(_list, ["ldy_imm", 0x00,             _id]);
    array_push(_list, ["label",   _lbl_scr2_nowrap]);
    array_push(_list, ["inx",     0,                _id]);
    array_push(_list, ["cpx_imm", _cam_w,           _id]);
    array_push(_list, ["beq",     _lbl_scr2_done,   _id]);
    array_push(_list, ["jmp_abs", _lbl_scr2_cols,   _id]);
    array_push(_list, ["label",   _lbl_scr2_done]);
    array_push(_list, ["rts",     0,                _id]);

    // ════════════════════════════════════════════════════════
    // colorMap — _row_count rows of colour into $D800
    // ════════════════════════════════════════════════════════
    if (_col_mode != 0) {
        array_push(_list, ["label",   _lbl_color]);
        array_push(_list, ["ldy_lab", _lbl_scrollx,      _id]);
        array_push(_list, ["ldx_imm", 0x00,              _id]);
        array_push(_list, ["label",   _lbl_color_cols]);
        for (var _r = 0; _r < _row_count; _r++) {
            array_push(_list, ["lda_aby", _map_base + _msz + ((_r + _start_row) * _map_w), _id]);
            array_push(_list, ["sta_abx", 0xD800          + ((_r + _start_row) * 40),       _id]);
        }
        array_push(_list, ["iny",     0,                 _id]);
        array_push(_list, ["cpy_imm", _map_w & 0xFF,     _id]);
        array_push(_list, ["bcc",     _lbl_color_nowrap, _id]);
        array_push(_list, ["ldy_imm", 0x00,              _id]);
        array_push(_list, ["label",   _lbl_color_nowrap]);
        array_push(_list, ["inx",     0,                 _id]);
        array_push(_list, ["cpx_imm", _cam_w,            _id]);
        array_push(_list, ["beq",     _lbl_color_done,   _id]);
        array_push(_list, ["jmp_abs", _lbl_color_cols,   _id]);
        array_push(_list, ["label",   _lbl_color_done]);
        array_push(_list, ["rts",     0,                 _id]);
    }

    // ── Spine resumes here after init ────────────────────────
    array_push(_list, ["label",   _lbl_after_init]);
    // No JSR here — your Main Loop node calls Scroller_L / Scroller_R.

    show_debug_message("MACRO_SCROLL: map=" + string(_map_w) + "x" + string(_map_h)
        + " base=$" + string_upper(decimal_to_hex(_map_base))
        + " col_mode=" + string(_col_mode)
        + " start_row=" + string(_start_row)
        + " row_count=" + string(_row_count)
        + " [unified delta core]");

} break;
	

// --------------------------------------------------------
// MACRO_VSCROLL
// --------------------------------------------------------
// 18-column map centred on 40-column screen (offset 11).
// Scrolling window: rows 1-22 (22 rows visible).
// Rows 0, 23, 24 blanked at init, never touched again.
// map_h = 22 (hardcoded, wraps/loops).
// Colour RAM always updated in lockstep with chars.
// Inner loop copies 18 bytes per row (not 40).
//
// Scroller_D : call once per frame to scroll content UP
//              (player moves down the map)
// Scroller_U : call once per frame to scroll content DOWN
//              (player moves up the map)
//
// Merged subroutines:
//   shcolsub    - forward copy, all ptrs advance +40 per row
//   shcolsubrev - reverse copy, all ptrs retreat -40 per row
// Both copy chars (screen RAM) and colour (CRAM) in the
// same inner loop, Y = 17..0 (18 bytes per row).
// Init uses separate shift_sub + col_sub (different src).
// --------------------------------------------------------
case "MACRO_VSCROLL": {

    var _id = _curr;

    if (!variable_instance_exists(_id, "scroll_alias") || _id.scroll_alias == "")
    {
        _id.scroll_alias = "vs" + string(real(_id));
    }
    var _p = _id.scroll_alias + "_";

    // ── Geometry ──────────────────────────────────────────
    var _map_stride  = 40;
    var _map_h       = 25;
    var _map_base    = 0x8000;
    if (instance_exists(obj_asset_manager))
    {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++)
        {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "MAP_DATA")
            {
                _map_base = _a.address;
                break;
            }
        }
    }

    // Visible window: rows 1..23 (23 rows), cols 1..38 (38 cols)
    // Row 0, row 24, col 0, col 39 are permanently blank — hide scroll edges
    var _num_rows   = 23;    // rows 1..23
    var _num_cols   = 38;    // cols 1..38
    var _col_start  = 1;     // first visible column on screen
    var _msz        = _map_stride * _map_h;
    var _scr        = 0x0400;

    // ── Labels ────────────────────────────────────────────
    var _lbl_scrolly   = _p + "scrolly";
    var _lbl_fine      = _p + "fine";
    var _lbl_skip      = _p + "skip";
    var _lbl_init      = _p + "init";
    var _lbl_after     = _p + "after";
    var _lbl_pending   = _p + "pending";
    var _lbl_def_scy   = _p + "def_scy";

    var _lbl_u_nofine  = _p + "u_nofine";
    var _lbl_u_nowrap  = _p + "u_nowrap";
    var _lbl_u_mullp   = _p + "u_mullp";
    var _lbl_u_muldn   = _p + "u_muldn";
    var _lbl_u_maplo   = _p + "u_maplo";
    var _lbl_u_maphi   = _p + "u_maphi";
    var _lbl_d_nofine  = _p + "d_nofine";
    var _lbl_d_nowrap  = _p + "d_nowrap";
    var _lbl_d_mullp   = _p + "d_mullp";
    var _lbl_d_maplo   = _p + "d_maplo";
    var _lbl_d_maphi   = _p + "d_maphi";

    // new-row fetch sub (shcolsub) statics
    var _lbl_sc_srcrlo  = _p + "sc_srcrlo";
    var _lbl_sc_srcrhi  = _p + "sc_srcrhi";
    var _lbl_sc_dstrlo  = _p + "sc_dstrlo";
    var _lbl_sc_dstrhi  = _p + "sc_dstrhi";
    var _lbl_sc_rowcnt  = _p + "sc_rowcnt";
    var _lbl_sc_ldalo   = _p + "sc_ldalo";
    var _lbl_sc_ldahi   = _p + "sc_ldahi";
    var _lbl_sc_stalo   = _p + "sc_stalo";
    var _lbl_sc_stahi   = _p + "sc_stahi";
    var _lbl_sc_rowlp   = _p + "sc_rowlp";
    var _lbl_sc_collp   = _p + "sc_collp";

    // init copy sub statics
    var _lbl_sh_srcrlo  = _p + "sh_srcrlo";
    var _lbl_sh_srcrhi  = _p + "sh_srcrhi";
    var _lbl_sh_dstrlo  = _p + "sh_dstrlo";
    var _lbl_sh_dstrhi  = _p + "sh_dstrhi";
    var _lbl_sh_rowcnt  = _p + "sh_rowcnt";
    var _lbl_sh_ldalo   = _p + "sh_ldalo";
    var _lbl_sh_ldahi   = _p + "sh_ldahi";
    var _lbl_sh_stalo   = _p + "sh_stalo";
    var _lbl_sh_stahi   = _p + "sh_stahi";
    var _lbl_sh_rowlp   = _p + "sh_rowlp";
    var _lbl_sh_collp   = _p + "sh_collp";
    var _lbl_shift_sub  = _p + "shiftsub";

    // speed-copy loop labels
    var _lbl_sd_xlp    = _p + "sd_xlp";
    var _lbl_sd_xdone  = _p + "sd_xdone";
    var _lbl_su_xlp    = _p + "su_xlp";
    var _lbl_su_xdone  = _p + "su_xdone";
    var _lbl_su_xlp2   = _p + "su_xlp2";
    var _lbl_su_xdone2 = _p + "su_xdone2";
    var _lbl_phase2    = _p + "phase2";

    // init zero labels
    var _lbl_zero1 = _p + "zero1";
    var _lbl_zero2 = _p + "zero2";
    var _lbl_zero3 = _p + "zero3";
    var _lbl_zero4 = _p + "zero4";
    var _lbl_blank_cols = _p + "blkcols";

    // Row base addresses baked at GML time
    // Visible rows 1.._num_rows, col_start offset baked into new-row fetch
    var _scr_row1 = _scr + 1 * 40;
    var _scr_row2 = _scr + 2 * 40;
    var _scr_rowN = _scr + _num_rows * 40;   // row 23 — new bottom for Scroller_D

    // ══════════════════════════════════════════════════════
    // Static data — jumped over at runtime
    // ══════════════════════════════════════════════════════
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);

    array_push(_list, ["label",   _lbl_scrolly]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_fine]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_pending]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_def_scy]);
    array_push(_list, ["byte",    0x00, _id]);

    // shcolsub (new-row fetch) statics
    array_push(_list, ["label",   _lbl_sc_srcrlo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sc_srcrhi]);
    array_push(_list, ["byte",    (_map_base >> 8) & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_sc_dstrlo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sc_dstrhi]);
    array_push(_list, ["byte",    0x04, _id]);
    array_push(_list, ["label",   _lbl_sc_rowcnt]);
    array_push(_list, ["byte",    0x00, _id]);

    // init copy statics
    array_push(_list, ["label",   _lbl_sh_srcrlo]);
    array_push(_list, ["byte",    (_map_base + _col_start) & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_sh_srcrhi]);
    array_push(_list, ["byte",    ((_map_base + _col_start) >> 8) & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_sh_dstrlo]);
    array_push(_list, ["byte",    (_scr_row1 + _col_start) & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_sh_dstrhi]);
    array_push(_list, ["byte",    ((_scr_row1 + _col_start) >> 8) & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_sh_rowcnt]);
    array_push(_list, ["byte",    0x00, _id]);

    // Scroller_D map statics
    array_push(_list, ["label",   _lbl_u_maplo]);
    array_push(_list, ["byte",    _map_base & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_u_maphi]);
    array_push(_list, ["byte",    (_map_base >> 8) & 0xFF, _id]);

    // Scroller_U map statics
    array_push(_list, ["label",   _lbl_d_maplo]);
    array_push(_list, ["byte",    _map_base & 0xFF, _id]);
    array_push(_list, ["label",   _lbl_d_maphi]);
    array_push(_list, ["byte",    (_map_base >> 8) & 0xFF, _id]);

    array_push(_list, ["label",   _lbl_skip]);

    // ══════════════════════════════════════════════════════
    // Entry
    // ══════════════════════════════════════════════════════
    array_push(_list, ["jsr",     _lbl_init,  _id]);
    array_push(_list, ["jmp_abs", _lbl_after, _id]);

    // ══════════════════════════════════════════════════════
    // Scroller_D — content moves UP (player moves down)
    //
    // Fine: decrement $D011 yscroll 7→0
    // Coarse: reset fine=7, inc scrollY, shift rows 2..23→1..22,
    //         fetch new bottom row into row 23
    // ══════════════════════════════════════════════════════
    array_push(_list, ["label",   "Scroller_D"]);

    var _lbl_d_iszero = _p + "d_iszero";
    array_push(_list, ["lda_lab", _lbl_fine,       _id]);
    array_push(_list, ["beq",     _lbl_d_iszero,   _id]);
    array_push(_list, ["jmp_abs", _lbl_u_nofine,   _id]);
    array_push(_list, ["label",   _lbl_d_iszero]);

    array_push(_list, ["lda_imm", 0x07,            _id]);
    array_push(_list, ["sta_lab", _lbl_fine,       _id]);
    array_push(_list, ["ora_imm", 0x17,            _id]);
    array_push(_list, ["sta_abs", 0xD011,          _id]);

    // Increment scrollY mod map_h
    array_push(_list, ["lda_lab", _lbl_scrolly,    _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 0x01,            _id]);
    array_push(_list, ["cmp_imm", _map_h & 0xFF,   _id]);
    array_push(_list, ["bcc",     _lbl_u_nowrap,   _id]);
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_u_nowrap]);
    array_push(_list, ["sta_lab", _lbl_scrolly,    _id]);

    // Speed-copy chars only: rows 2..23 → 1..22
    // X = absolute screen column (_col_start .. _col_start+_num_cols-1)
    array_push(_list, ["ldx_imm", _col_start,      _id]);
    array_push(_list, ["label",   _lbl_sd_xlp]);
    for (var _ri = 1; _ri <= _num_rows - 1; _ri++)
    {
        var _sa = _scr + (_ri + 1) * 40;
        var _da = _scr + _ri * 40;
        array_push(_list, ["lda_abx", _sa, _id]);
        array_push(_list, ["sta_abx", _da, _id]);
    }
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["cpx_imm", _col_start + _num_cols, _id]);
    array_push(_list, ["beq",     _lbl_sd_xdone,   _id]);
    array_push(_list, ["jmp_abs", _lbl_sd_xlp,     _id]);
    array_push(_list, ["label",   _lbl_sd_xdone]);

    // Compute new bottom map row index = (scrollY + _num_rows - 1) mod map_h
    array_push(_list, ["lda_lab", _lbl_scrolly,    _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", (_num_rows - 1) & 0xFF, _id]);
    array_push(_list, ["cmp_imm", _map_h & 0xFF,   _id]);
    array_push(_list, ["bcc",     _lbl_u_muldn,    _id]);
    array_push(_list, ["sbc_imm", _map_h & 0xFF,   _id]);
    array_push(_list, ["label",   _lbl_u_muldn]);

    // Multiply × map_stride
    array_push(_list, ["tax",     0,               _id]);
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_u_maplo,    _id]);
    array_push(_list, ["sta_lab", _lbl_u_maphi,    _id]);
    array_push(_list, ["cpx_imm", 0x00,            _id]);
    array_push(_list, ["beq",     _lbl_u_mullp,    _id]);
    var _lbl_u_mloop = _p + "u_mloop";
    array_push(_list, ["label",   _lbl_u_mloop]);
    array_push(_list, ["lda_lab", _lbl_u_maplo,    _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", _map_stride & 0xFF, _id]);
    array_push(_list, ["sta_lab", _lbl_u_maplo,    _id]);
    array_push(_list, ["lda_lab", _lbl_u_maphi,    _id]);
    array_push(_list, ["adc_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_u_maphi,    _id]);
    array_push(_list, ["dex",     0,               _id]);
    array_push(_list, ["bne",     _lbl_u_mloop,    _id]);
    array_push(_list, ["label",   _lbl_u_mullp]);

    // Add map_base + col_start
    array_push(_list, ["lda_lab", _lbl_u_maplo,                          _id]);
    array_push(_list, ["clc",     0,                                     _id]);
    array_push(_list, ["adc_imm", (_map_base + _col_start) & 0xFF,       _id]);
    array_push(_list, ["sta_lab", _lbl_u_maplo,                          _id]);
    array_push(_list, ["lda_lab", _lbl_u_maphi,                          _id]);
    array_push(_list, ["adc_imm", ((_map_base + _col_start) >> 8) & 0xFF,_id]);
    array_push(_list, ["sta_lab", _lbl_u_maphi,                          _id]);

    // Fetch new bottom row → screen row _num_rows col _col_start
    array_push(_list, ["lda_lab", _lbl_u_maplo,                      _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrlo,                    _id]);
    array_push(_list, ["lda_lab", _lbl_u_maphi,                      _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrhi,                    _id]);
    array_push(_list, ["lda_imm", (_scr_rowN + _col_start) & 0xFF,   _id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrlo,                    _id]);
    array_push(_list, ["lda_imm", ((_scr_rowN + _col_start) >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrhi,                    _id]);
    array_push(_list, ["lda_imm", 1,                                 _id]);
    array_push(_list, ["sta_lab", _lbl_sc_rowcnt,                    _id]);
    array_push(_list, ["jsr",     _p + "shcolsub",                   _id]);

    array_push(_list, ["rts",     0,                                 _id]);

    // D fine tick
    array_push(_list, ["label",   _lbl_u_nofine]);
    array_push(_list, ["lda_lab", _lbl_fine,       _id]);
    array_push(_list, ["sec",     0,               _id]);
    array_push(_list, ["sbc_imm", 0x01,            _id]);
    array_push(_list, ["sta_lab", _lbl_fine,       _id]);
    array_push(_list, ["and_imm", 0x07,            _id]);
    array_push(_list, ["ora_imm", 0x10,            _id]);
    array_push(_list, ["sta_abs", 0xD011,          _id]);
    array_push(_list, ["rts",     0,               _id]);

    // ══════════════════════════════════════════════════════
    // Scroller_U — content moves DOWN (player moves up)
    //
    // Fine: increment $D011 yscroll 0→7
    // Coarse sets pending=1, returns.
    // Phase 1 (next frame): wait raster, $D011=0,
    //                       shift chars rows 1..22→2..23,
    //                       set pending=2, return.
    // Phase 2 (next frame): fetch new top row → row 1,
    //                       clear pending, return.
    // ══════════════════════════════════════════════════════
    array_push(_list, ["label",   "Scroller_U"]);

    var _lbl_u_nopend  = _p + "u_nopend";
    var _lbl_u_dopend  = _p + "u_dopend";
    var _lbl_u_nowrap2 = _p + "u_nowrap2";

    array_push(_list, ["lda_lab", _lbl_pending,    _id]);
    array_push(_list, ["beq",     _lbl_u_nopend,   _id]);
    array_push(_list, ["jmp_abs", _lbl_u_dopend,   _id]);
    array_push(_list, ["label",   _lbl_u_nopend]);

    // Fine tick
    array_push(_list, ["lda_lab", _lbl_fine,       _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 0x01,            _id]);
    array_push(_list, ["sta_lab", _lbl_fine,       _id]);
    array_push(_list, ["and_imm", 0x07,            _id]);
    array_push(_list, ["ora_imm", 0x10,            _id]);
    array_push(_list, ["sta_abs", 0xD011,          _id]);

    // Coarse threshold
    array_push(_list, ["lda_lab", _lbl_fine,       _id]);
    array_push(_list, ["cmp_imm", 0x07,            _id]);
    array_push(_list, ["bcc",     _lbl_d_nofine,   _id]);

    // Coarse: reset fine, dec scrollY, save, set pending=1
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_fine,       _id]);
    array_push(_list, ["lda_lab", _lbl_scrolly,    _id]);
    array_push(_list, ["bne",     _lbl_u_nowrap2,  _id]);
    array_push(_list, ["lda_imm", _map_h & 0xFF,   _id]);
    array_push(_list, ["label",   _lbl_u_nowrap2]);
    array_push(_list, ["sec",     0,               _id]);
    array_push(_list, ["sbc_imm", 0x01,            _id]);
    array_push(_list, ["sta_lab", _lbl_scrolly,    _id]);
    array_push(_list, ["sta_lab", _lbl_def_scy,    _id]);
    array_push(_list, ["lda_imm", 0x01,            _id]);
    array_push(_list, ["sta_lab", _lbl_pending,    _id]);
    array_push(_list, ["rts",     0,               _id]);

    array_push(_list, ["label",   _lbl_d_nofine]);
    array_push(_list, ["rts",     0,               _id]);

    // Deferred handler
    array_push(_list, ["label",   _lbl_u_dopend]);

    array_push(_list, ["lda_lab", _lbl_pending,    _id]);
    array_push(_list, ["cmp_imm", 0x02,            _id]);
    array_push(_list, ["beq",     _lbl_phase2,     _id]);

    // ── Phase 1 — wait raster, write $D011, shift chars ──
    var _lbl_vwlo = _p + "vwlo";
    var _lbl_vwhi = _p + "vwhi";
    array_push(_list, ["label",   _lbl_vwlo]);
    array_push(_list, ["lda_abs", 0xD012,          _id]);
    array_push(_list, ["cmp_imm", 0xFA,            _id]);
    array_push(_list, ["bne",     _lbl_vwlo,       _id]);
    array_push(_list, ["label",   _lbl_vwhi]);
    array_push(_list, ["lda_abs", 0xD012,          _id]);
    array_push(_list, ["cmp_imm", 0xFA,            _id]);
    array_push(_list, ["beq",     _lbl_vwhi,       _id]);
    array_push(_list, ["lda_imm", 0x10,            _id]);
    array_push(_list, ["sta_abs", 0xD011,          _id]);

    // Shift chars only: rows 1..22 → 2..23, bottom-up, X = screen col
    array_push(_list, ["ldx_imm", _col_start,      _id]);
    array_push(_list, ["label",   _lbl_su_xlp]);
    for (var _ri = _num_rows - 1; _ri >= 1; _ri--)
    {
        var _sa = _scr + _ri * 40;
        var _da = _scr + (_ri + 1) * 40;
        array_push(_list, ["lda_abx", _sa, _id]);
        array_push(_list, ["sta_abx", _da, _id]);
    }
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["cpx_imm", _col_start + _num_cols, _id]);
    array_push(_list, ["beq",     _lbl_su_xdone,   _id]);
    array_push(_list, ["jmp_abs", _lbl_su_xlp,     _id]);
    array_push(_list, ["label",   _lbl_su_xdone]);

    array_push(_list, ["lda_imm", 0x02,            _id]);
    array_push(_list, ["sta_lab", _lbl_pending,    _id]);
    array_push(_list, ["rts",     0,               _id]);

    // ── Phase 2 — fetch new top row, clear pending ────────
    array_push(_list, ["label",   _lbl_phase2]);

    // Multiply def_scy × map_stride into d_maplo/hi
    // Zero the accumulator first
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_d_maplo,    _id]);
    array_push(_list, ["sta_lab", _lbl_d_maphi,    _id]);

    // Load row index into X — if zero, skip multiply entirely
    array_push(_list, ["ldx_lab", _lbl_def_scy,    _id]);
    var _lbl_dm_loop   = _p + "dm_lp";
    var _lbl_dm_done   = _p + "dm_done";
    array_push(_list, ["cpx_imm", 0x00,            _id]);
    array_push(_list, ["beq",     _lbl_dm_done,    _id]);
    array_push(_list, ["label",   _lbl_dm_loop]);
    array_push(_list, ["lda_lab", _lbl_d_maplo,    _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", _map_stride & 0xFF, _id]);
    array_push(_list, ["sta_lab", _lbl_d_maplo,    _id]);
    array_push(_list, ["lda_lab", _lbl_d_maphi,    _id]);
    array_push(_list, ["adc_imm", (_map_stride >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_lab", _lbl_d_maphi,    _id]);
    array_push(_list, ["dex",     0,               _id]);
    array_push(_list, ["bne",     _lbl_dm_loop,    _id]);
    array_push(_list, ["label",   _lbl_dm_done]);

    // Add map_base + col_start to get final map row address
    array_push(_list, ["lda_lab", _lbl_d_maplo,                          _id]);
    array_push(_list, ["clc",     0,                                     _id]);
    array_push(_list, ["adc_imm", (_map_base + _col_start) & 0xFF,       _id]);
    array_push(_list, ["sta_lab", _lbl_d_maplo,                          _id]);
    array_push(_list, ["lda_lab", _lbl_d_maphi,                          _id]);
    array_push(_list, ["adc_imm", ((_map_base + _col_start) >> 8) & 0xFF,_id]);
    array_push(_list, ["sta_lab", _lbl_d_maphi,                          _id]);

    // Set up shcolsub: src = map row, dst = screen row 1 col _col_start
    array_push(_list, ["lda_lab", _lbl_d_maplo,                          _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrlo,                        _id]);
    array_push(_list, ["lda_lab", _lbl_d_maphi,                          _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrhi,                        _id]);
    array_push(_list, ["lda_imm", (_scr_row1 + _col_start) & 0xFF,       _id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrlo,                        _id]);
    array_push(_list, ["lda_imm", ((_scr_row1 + _col_start) >> 8) & 0xFF,_id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrhi,                        _id]);
    array_push(_list, ["lda_imm", 1,                                     _id]);
    array_push(_list, ["sta_lab", _lbl_sc_rowcnt,                        _id]);
    array_push(_list, ["jsr",     _p + "shcolsub",                       _id]);

    // Done — clear pending
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_pending,    _id]);
    array_push(_list, ["rts",     0,               _id]);

    // ══════════════════════════════════════════════════════
    // shcolsub — fetch one map row into screen RAM
    // Copies sc_rowcnt rows of _num_cols bytes (Y = _num_cols-1..0)
    // from map (sc_srcrlo/hi) to screen (sc_dstrlo/hi).
    // Advances both pointers +40 per row.
    // ══════════════════════════════════════════════════════
    array_push(_list, ["label",   _p + "shcolsub"]);

    array_push(_list, ["lda_lab", _lbl_sc_srcrlo,  _id]);
    array_push(_list, ["sta_lab", _lbl_sc_ldalo,   _id]);
    array_push(_list, ["lda_lab", _lbl_sc_srcrhi,  _id]);
    array_push(_list, ["sta_lab", _lbl_sc_ldahi,   _id]);
    array_push(_list, ["lda_lab", _lbl_sc_dstrlo,  _id]);
    array_push(_list, ["sta_lab", _lbl_sc_stalo,   _id]);
    array_push(_list, ["lda_lab", _lbl_sc_dstrhi,  _id]);
    array_push(_list, ["sta_lab", _lbl_sc_stahi,   _id]);

    array_push(_list, ["label",   _lbl_sc_rowlp]);
    array_push(_list, ["ldy_imm", _num_cols - 1,   _id]);

    array_push(_list, ["label",   _lbl_sc_collp]);
    array_push(_list, ["byte",    0xB9, _id]);
    array_push(_list, ["label",   _lbl_sc_ldalo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sc_ldahi]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["byte",    0x99, _id]);
    array_push(_list, ["label",   _lbl_sc_stalo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sc_stahi]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["dey",     0,               _id]);
    array_push(_list, ["bpl",     _lbl_sc_collp,   _id]);

    array_push(_list, ["lda_lab", _lbl_sc_ldalo,   _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 40,              _id]);
    array_push(_list, ["sta_lab", _lbl_sc_ldalo,   _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrlo,  _id]);
    array_push(_list, ["lda_lab", _lbl_sc_ldahi,   _id]);
    array_push(_list, ["adc_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_sc_ldahi,   _id]);
    array_push(_list, ["sta_lab", _lbl_sc_srcrhi,  _id]);

    array_push(_list, ["lda_lab", _lbl_sc_stalo,   _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 40,              _id]);
    array_push(_list, ["sta_lab", _lbl_sc_stalo,   _id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrlo,  _id]);
    array_push(_list, ["lda_lab", _lbl_sc_stahi,   _id]);
    array_push(_list, ["adc_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_sc_stahi,   _id]);
    array_push(_list, ["sta_lab", _lbl_sc_dstrhi,  _id]);

    array_push(_list, ["dec_lab", _lbl_sc_rowcnt,  _id]);
    array_push(_list, ["bne",     _lbl_sc_rowlp,   _id]);
    array_push(_list, ["rts",     0,               _id]);

    // ══════════════════════════════════════════════════════
    // shift_sub — init chars copy, map→screen
    // ══════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_shift_sub]);

    array_push(_list, ["lda_lab", _lbl_sh_srcrlo,  _id]);
    array_push(_list, ["sta_lab", _lbl_sh_ldalo,   _id]);
    array_push(_list, ["lda_lab", _lbl_sh_srcrhi,  _id]);
    array_push(_list, ["sta_lab", _lbl_sh_ldahi,   _id]);
    array_push(_list, ["lda_lab", _lbl_sh_dstrlo,  _id]);
    array_push(_list, ["sta_lab", _lbl_sh_stalo,   _id]);
    array_push(_list, ["lda_lab", _lbl_sh_dstrhi,  _id]);
    array_push(_list, ["sta_lab", _lbl_sh_stahi,   _id]);

    array_push(_list, ["label",   _lbl_sh_rowlp]);
    array_push(_list, ["ldy_imm", _num_cols - 1,   _id]);

    array_push(_list, ["label",   _lbl_sh_collp]);
    array_push(_list, ["byte",    0xB9, _id]);
    array_push(_list, ["label",   _lbl_sh_ldalo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sh_ldahi]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["byte",    0x99, _id]);
    array_push(_list, ["label",   _lbl_sh_stalo]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _lbl_sh_stahi]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["dey",     0,               _id]);
    array_push(_list, ["bpl",     _lbl_sh_collp,   _id]);

    array_push(_list, ["lda_lab", _lbl_sh_ldalo,   _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 40,              _id]);
    array_push(_list, ["sta_lab", _lbl_sh_ldalo,   _id]);
    array_push(_list, ["sta_lab", _lbl_sh_srcrlo,  _id]);
    array_push(_list, ["lda_lab", _lbl_sh_ldahi,   _id]);
    array_push(_list, ["adc_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_sh_ldahi,   _id]);
    array_push(_list, ["sta_lab", _lbl_sh_srcrhi,  _id]);

    array_push(_list, ["lda_lab", _lbl_sh_stalo,   _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_imm", 40,              _id]);
    array_push(_list, ["sta_lab", _lbl_sh_stalo,   _id]);
    array_push(_list, ["sta_lab", _lbl_sh_dstrlo,  _id]);
    array_push(_list, ["lda_lab", _lbl_sh_stahi,   _id]);
    array_push(_list, ["adc_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_sh_stahi,   _id]);
    array_push(_list, ["sta_lab", _lbl_sh_dstrhi,  _id]);

    array_push(_list, ["dec_lab", _lbl_sh_rowcnt,  _id]);
    array_push(_list, ["bne",     _lbl_sh_rowlp,   _id]);
    array_push(_list, ["rts",     0,               _id]);

    // ══════════════════════════════════════════════════════
    // Init — run once at startup
    //
    // 1. scrollY=0, fine=0, $D011=yscroll 0
    // 2. Clear full screen to space ($20)
    // 3. Copy _num_rows map rows → screen rows 1.._num_rows col _col_start
    // 4. Write space ($20) to col 0 and col 39 of every row — edge fade
    // 5. Write space ($20) to row 0 and row 24 — top/bottom fade
    // ══════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_init]);

    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_lab", _lbl_scrolly,    _id]);
    array_push(_list, ["sta_lab", _lbl_fine,       _id]);
    // 24-row mode ($D011 bit3=0), yscroll=3, display on
    array_push(_list, ["lda_imm", 0x13,            _id]);
    array_push(_list, ["sta_abs", 0xD011,          _id]);
    // 38-column mode ($D016 bit3=0), xscroll=0
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["sta_abs", 0xD016,          _id]);

    // Clear full screen RAM to space
    array_push(_list, ["lda_imm", 0x20,            _id]);
    array_push(_list, ["ldx_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_zero1]);
    array_push(_list, ["sta_abx", _scr,            _id]);
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["bne",     _lbl_zero1,      _id]);
    array_push(_list, ["ldx_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_zero2]);
    array_push(_list, ["sta_abx", _scr + 0x100,    _id]);
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["bne",     _lbl_zero2,      _id]);
    array_push(_list, ["ldx_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_zero3]);
    array_push(_list, ["sta_abx", _scr + 0x200,    _id]);
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["bne",     _lbl_zero3,      _id]);
    array_push(_list, ["ldx_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_zero4]);
    array_push(_list, ["sta_abx", _scr + 0x300,    _id]);
    array_push(_list, ["inx",     0,               _id]);
    array_push(_list, ["cpx_imm", 0xE8,            _id]);
    array_push(_list, ["bne",     _lbl_zero4,      _id]);

    // Copy _num_rows tile rows: map row 0.._num_rows-1 → screen rows 1.._num_rows
    array_push(_list, ["lda_imm", (_map_base + _col_start) & 0xFF,            _id]);
    array_push(_list, ["sta_lab", _lbl_sh_srcrlo,                             _id]);
    array_push(_list, ["lda_imm", ((_map_base + _col_start) >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_lab", _lbl_sh_srcrhi,                             _id]);
    array_push(_list, ["lda_imm", (_scr_row1 + _col_start) & 0xFF,            _id]);
    array_push(_list, ["sta_lab", _lbl_sh_dstrlo,                             _id]);
    array_push(_list, ["lda_imm", ((_scr_row1 + _col_start) >> 8) & 0xFF,     _id]);
    array_push(_list, ["sta_lab", _lbl_sh_dstrhi,                             _id]);
    array_push(_list, ["lda_imm", _num_rows,                                  _id]);
    array_push(_list, ["sta_lab", _lbl_sh_rowcnt,                             _id]);
    array_push(_list, ["jsr",     _lbl_shift_sub,                             _id]);

    // Write space to col 0 and col 39 for all 25 rows — permanent edge blank
    // Use X as row index 0..24, write _scr + row*40 + 0 and _scr + row*40 + 39
    array_push(_list, ["lda_imm", 0x20,            _id]);
    var _lbl_blank_cols = _p + "blkcols";
    array_push(_list, ["ldx_imm", 0x00,            _id]);
    array_push(_list, ["label",   _lbl_blank_cols]);
    // Write left edge col 0 and right edge col 39 for this row via abs,X
    // X = row * 40 offset from _scr — but X is only 8-bit so use Y for col
    // Simpler: unroll all 25 rows at GML time
    for (var _row = 0; _row <= 24; _row++)
    {
        array_push(_list, ["sta_abs", _scr + _row * 40 + 0,  _id]);
        array_push(_list, ["sta_abs", _scr + _row * 40 + 39, _id]);
    }

    array_push(_list, ["rts",     0,               _id]);

    // ── Spine resumes ─────────────────────────────────────
    array_push(_list, ["label",   _lbl_after]);

    show_debug_message("MACRO_VSCROLL: " + string(_num_rows) + "r x "
        + string(_num_cols) + "c  col_start=" + string(_col_start)
        + "  map=" + string(_map_stride) + "x" + string(_map_h)
        + "  base=$" + string_upper(decimal_to_hex(_map_base)));

} break;
// --------------------------------------------------------
// MACRO_CHR - Set up character set and colours
// --------------------------------------------------------
case "MACRO_CHR": {
		    var _asset_name = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";
		    var _src_addr   = 0x2000; // default
		    var _char_size  = 2048;   // default 2KB
		    // Look up asset to get source address and size
		    if (instance_exists(obj_asset_manager) && _asset_name != "") {
		        var _am = obj_asset_manager;
		        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
		            var _a = ds_list_find_value(_am.asset_list, _ai);
		            if (_a.type == "CHAR_SET" && _a.name == _asset_name) {
		                _src_addr  = _a.address;
		                if (buffer_exists(_a.buffer)) _char_size = buffer_get_size(_a.buffer);
		                break;
		            }
		        }
		    }
		    var _dst_addr = _src_addr; // always equal — no runtime copy needed
			//3

		    // If src == dst the asset is already at the right place in the PRG —
		    // no copy needed at runtime, emit nothing.
		    // If they differ, emit a copy loop.
		    if (_src_addr != _dst_addr) {
		        var _pages = ceil(_char_size / 256);
		        for (var _pg = 0; _pg < _pages; _pg++) {
		            var _lbl      = "chr_copy_" + string(_pg) + "_" + string(real(_curr));
		            var _page_src = _src_addr + (_pg * 256);
		            var _page_dst = _dst_addr + (_pg * 256);
		            var _page_sz  = min(256, _char_size - (_pg * 256));
		            array_push(_list, ["ldx_imm", 0,         _curr]);
		            array_push(_list, ["label",   _lbl              ]);
		            array_push(_list, ["lda_abx", _page_src, _curr]);
		            array_push(_list, ["sta_abx", _page_dst, _curr]);
		            array_push(_list, ["inx",     0,         _curr]);
		            array_push(_list, ["cpx_imm", _page_sz,  _curr]);
		            array_push(_list, ["bne",     _lbl,      _curr]);
		        }
		    }
			// If src == dst: asset injected into PRG at the right address by the
		    // build pass — VIC will read it directly. Nothing to emit here.

// If a MACRO_MAP is on the spine, it owns $D016 and colours — only emit $D018
        var _chr_has_map = false;
        with (obj_c64_node) {
            if ((node_type == "MACRO_MAP" || node_type == "MACRO_METAMAP") && is_connected && org_parent == noone)
                { _chr_has_map = true; break; }
        }
        // Resolve whether the linked CHAR_SET is ECM — if so, the forced
        // $D011 restore below (slots 1+2) must not clobber bit 6, or MACRO_VIC's
        // ECM enable gets silently undone the moment MACRO_CHR runs on the spine.
        var _chr_is_ecm = false;
        if (instance_exists(obj_asset_manager) && _asset_name != "") {
            var _chr_amc = obj_asset_manager;
            for (var _chr_ci = 0; _chr_ci < ds_list_size(_chr_amc.asset_list); _chr_ci++) {
                var _chr_ca = ds_list_find_value(_chr_amc.asset_list, _chr_ci);
                if (_chr_ca.type == "CHAR_SET" && _chr_ca.name == _asset_name) {
                    _chr_is_ecm = variable_struct_exists(_chr_ca.meta, "mc_mode") && (_chr_ca.meta.mc_mode == 2);
                    break;
                }
            }
        }

        // Always emit VIC setup instructions (slots 1+)
        // slots: 1=$D011, 2=sta D011, 3=$D016, 4=sta D016, 5=$D018, 6=sta D018, 7+=colours
        for (var _cj = 1; _cj < array_length(_curr.instructions); _cj++) {
            // Skip $D016 sta (slot 4), $D021 (slot 8), $D022 (slot 10), $D023 (slot 12)
            // when map is present — map owns mode and colours
            // Map owns $D011, $D016 and all colours — only emit $D018 (slots 5+6)
            // Map owns $D016 and colours — but CHR must still restore $D011 to text mode
        // after a potential MACRO_BMP. Allow slots 1+2 ($D011) and 5+6 ($D018) through.
        if (_chr_has_map && (_cj != 1 && _cj != 2 && _cj != 5 && _cj != 6)) continue;
            var _vic_instr = array_create(3);
            _vic_instr[0] = _curr.instructions[_cj][0];
            _vic_instr[1] = (array_length(_curr.instructions[_cj]) > 1) ? _curr.instructions[_cj][1] : 7; // bug with background defaulting to 0
            // Slot 1 is the $D011 immediate value — force bit 6 (ECM) back on
            // if the linked charset is ECM, so this restore-write can't undo
            // MACRO_VIC's ECM enable.
            if (_cj == 1 && _chr_is_ecm && is_real(_vic_instr[1])) {
                _vic_instr[1] = real(_vic_instr[1]) | 0x40;
            }
            _vic_instr[2] = _curr;
            array_push(_list, _vic_instr);
        }

		} break;
	
// --------------------------------------------------------
// MACRO_TEXT_SCROLL
// --------------------------------------------------------
case "MACRO_TEXT_SCROLL": {
    

var _id = _curr;
    var _saved_alias = (array_length(_id.instructions[0]) > 12 && is_string(_id.instructions[0][12])) ? string(_id.instructions[0][12]) : "";
    // Strip any old instance-ID-based aliases (start with "ts" followed by digits only)
    if (string_pos("ts", _saved_alias) == 1) {
        var _suffix = string_copy(_saved_alias, 3, string_length(_saved_alias) - 2);
        if (string_digits(_suffix) == _suffix && string_length(_suffix) > 3) _saved_alias = "";
    }
    var _p = (_saved_alias != "") ? (_saved_alias + "_") : ("ts" + string(real(_id)) + "_");
    // Save cleaned alias back
    if (_saved_alias == "" && array_length(_id.instructions[0]) > 12) {
        _id.instructions[0][12] = "";
    }
    var _row      = is_real(_curr.instructions[0][1]) ? clamp(real(_curr.instructions[0][1]), 0, 24) : 23;
    var _colour   = is_real(_curr.instructions[0][2]) ? clamp(real(_curr.instructions[0][2]), 0, 15) : 1;
    var _speed    = is_real(_curr.instructions[0][3]) ? clamp(real(_curr.instructions[0][3]), 1,  7) : 2;
    var _dir      = 0; // direction removed — left scroll only
    var _txt_addr = is_real(_curr.instructions[0][5]) ? real(_curr.instructions[0][5]) : 0xC000;
	var _text_src  = (array_length(_curr.instructions[0]) > 9  && is_real(_curr.instructions[0][9]))  ? real(_curr.instructions[0][9])  : 0;
    var _asset_nm  = (array_length(_curr.instructions[0]) > 10) ? string(_curr.instructions[0][10]) : "";
    var _txt_str   = string(_curr.instructions[0][6]);

    // Resolve Charset Asset Name -> Address
    var _charset_nm = (array_length(_curr.instructions[0]) > 13) ? string(_curr.instructions[0][13]) : "";
    var _charset_addr = 0;
    if (_charset_nm != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _ta = ds_list_find_value(_am.asset_list, _i);
            if (_ta.type == "CHAR_SET" && _ta.name == _charset_nm) {
                if (variable_struct_exists(_ta, "address")) _charset_addr = _ta.address;
                break;
            }
        }
    }
    // Bank 0, Screen at $0400 (bits 4-7 = 1) | Charset offset (bits 1-3)
    var _d018_val = (_charset_addr == 0) ? 0x15 : (0x10 | (((_charset_addr & 0x3FFF) div 2048) << 1));
    show_debug_message("CHARSET: nm=" + string(_charset_nm) + " addr=$" + string_upper(decimal_to_hex(_charset_addr)) + " d018=$" + string_upper(decimal_to_hex(_d018_val)));

    if (_text_src == 1 && _asset_nm != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _tai = 0; _tai < ds_list_size(_am.asset_list); _tai++) {
            var _ta = ds_list_find_value(_am.asset_list, _tai);
            if (_ta.type == "TEXT_DATA" && _ta.name == _asset_nm) {
                _txt_str = _ta.meta.text;
                if (variable_struct_exists(_ta, "address")) {
                    _txt_addr = _ta.address;
                    _curr.instructions[0][5] = _txt_addr;
                }
                break;
            }
        }
    }
    var _pre_nop  = (array_length(_curr.instructions[0]) > 7 && is_real(_curr.instructions[0][7])) ? clamp(real(_curr.instructions[0][7]), 0, 255) : 6;
    var _post_nop = (array_length(_curr.instructions[0]) > 8 && is_real(_curr.instructions[0][8])) ? clamp(real(_curr.instructions[0][8]), 0, 255) : 27;
var _use_sid = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _use_sid = 1; break; }
    }
var _jsr_mode = (array_length(_curr.instructions[0]) > 11 && is_real(_curr.instructions[0][11])) ? real(_curr.instructions[0][11]) : 0;


// Resolve multicolour mode early — needed for $D016 save/restore values
    var _ts_map_mode = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_MAP" && is_connected) {
            _ts_map_mode = (array_length(instructions[0]) > 4) ? real(instructions[0][4]) : 0;
            break; // Map is master, so we can stop looking
        } else if (node_type == "MACRO_CHR" && is_connected && org_parent == noone) {
            _ts_map_mode = (array_length(instructions[0]) > 2) ? real(instructions[0][2]) : 0;
        }
    }
	// C64 Hardware Rule: In MC mode, Colour RAM bit 3 must be SET (value >= 8) 
    // for the character to actually render in multicolour.
    if (_ts_map_mode == 1) {
        _colour = (_colour & 7) | 8;
    }
	
    var _ts_d016 = (_ts_map_mode == 1) ? 0x18 : 0x08;

    var _scr_row  = 0x0400 + (_row * 40);
    var _col_row  = 0xD800 + (_row * 40);
	var _raster_finetune = 0; // for finetuning
    var _raster   = clamp(50 + (_row * 8) +_raster_finetune , 0, 255); 

    // Labels
    var _IRQ      = _p + "irq";
    var _INIT     = _p + "init";
    var _SINIT    = _p + "sinit";
    var _SCRL     = _p + "scrl";
    var _SKIP     = _p + "skip";

    // Variable labels (resolved by _lab fixups)
    var _v_flag   = _p + "vflag";
    var _v_saveA  = _p + "vsaveA";
    var _v_saveX  = _p + "vsaveX";
    var _v_saveY  = _p + "vsaveY";
    var _v_colour = _p + "vcol";
    var _v_dir    = _p + "vdir";
    var _v_waitc  = _p + "vwaitc";
    var _v_pause  = _p + "vpause";
	var _v_speed0 = _p + "vspd0";
    var _v_speed1 = _p + "vspd1";
	var _v_d011   = _p + "vd011";
	var _v_d016   = _p + "vd016";
	var _v_d018   = _p + "vd018";
	var _v_dd00   = _p + "vdd00";

    show_debug_message("MACRO_TEXT_SCROLL: row=" + string(_row) + " use_sid=" + string(_use_sid) +
        " raster=$" + string_upper(decimal_to_hex(_raster)) +
        " scr_row=$" + string_upper(decimal_to_hex(_scr_row)) +
        " txt=$"     + string_upper(decimal_to_hex(_txt_addr)));

// ════════════════════════════════════════════════════════
    // STANDALONE MODE — not supported, requires MACRO_SID
    // Warning is shown on the node itself
    // ════════════════════════════════════════════════════════
if (_use_sid == 0) {

        array_push(_list, ["jsr",      _SINIT,  _id]);
        if (_jsr_mode == 0) {
            array_push(_list, ["label",    _SKIP]);
            array_push(_list, ["jmp",      _SKIP,   _id]); // infinite loop — no SID present
        } else {
            array_push(_list, ["jmp_abs",  _SKIP,   _id]);
        }

    // ════════════════════════════════════════════════════════
    // SID MODE
    // ════════════════════════════════════════════════════════
} else {


        array_push(_list, ["jsr",      _SINIT,  _id]);

if (_jsr_mode == 0) {
            // Original blocking mloop — scroller owns the main loop
            array_push(_list, ["label",    _p + "mloop"]);
            array_push(_list, ["lda_lab",  _v_flag,       _id]);
            array_push(_list, ["beq",      _p + "mloop",  _id]);
            array_push(_list, ["lda_imm",  0x00,          _id]);
            array_push(_list, ["sta_lab",  _v_flag,       _id]);
            array_push(_list, ["jsr",      _SCRL,         _id]);
            array_push(_list, ["jmp",      _p + "mloop",  _id]);
        } else {
            // JSR MODE — no mloop at all, just init and fall through
            // User must JSR to _SCRL from their own main loop each frame
            array_push(_list, ["jmp_abs",  _SKIP,         _id]);
        }

        // ── SCROLL IRQ ────────────────────────────────────────────────
        array_push(_list, ["label",      _p + "scroll"]);
		
//repeat(_nop_delay) { array_push(_list, ["nop", 0, _id]); } // entry delay — tune this value
		
        array_push(_list, ["lda_imm",   0xFF,                           _id]);
        array_push(_list, ["sta_abs",   0xD019,                         _id]); // ack VIC IRQ
        // PRE-NOP Delay
		 repeat(_pre_nop) { array_push(_list, ["nop", 0, _id]); }
        array_push(_list, ["lda_abs",   0xD011,                         _id]);
        array_push(_list, ["sta_lab",   _v_d011,                        _id]);
        array_push(_list, ["lda_abs",   0xD016,                         _id]);
        array_push(_list, ["sta_lab",   _v_d016,                        _id]);
        array_push(_list, ["lda_abs",   0xD018,                         _id]);
        array_push(_list, ["sta_lab",   _v_d018,                        _id]);
        array_push(_list, ["lda_abs",   0xDD00,                         _id]);
        array_push(_list, ["sta_lab",   _v_dd00,                        _id]);
        // Switch to bank 0 + text mode for scroll row

		
        array_push(_list, ["and_imm",   0xFC,                           _id]); // A still has $DD00
        //array_push(_list, ["ora_imm",   0x03,                           _id]); // bank 0
        //array_push(_list, ["sta_abs",   0xDD00,                         _id]);
        //array_push(_list, ["lda_imm",   0x15,                           _id]); // screen $0400, ROM charset
        //array_push(_list, ["sta_abs",   0xD018,                         _id]);
		
		array_push(_list, ["ora_imm",   0x03,                           _id]); // bank 0
        array_push(_list, ["sta_abs",   0xDD00,                         _id]);
        array_push(_list, ["lda_imm",   _d018_val,                      _id]); // screen $0400, mapped charset
        array_push(_list, ["sta_abs",   0xD018,                         _id]);
		
		
        array_push(_list, ["lda_imm",   0x1B,                           _id]); // text mode
        array_push(_list, ["sta_abs",   0xD011,                         _id]);
        // Set flag for main loop to do scroll work
        array_push(_list, ["lda_imm",   0x01,                           _id]);
        array_push(_list, ["sta_lab",   _v_flag,                        _id]);
// Wait until we are AT the scroll row raster before touching $D016
        // This prevents map rows above seeing HR mode during the IRQ setup
        var _rw2 = _p + "rw2";
        array_push(_list, ["lda_imm",    _raster & 0xFF,               _id]);
        array_push(_list, ["label",      _rw2]);
        array_push(_list, ["cmp_abs",    0xD012,                       _id]);
        array_push(_list, ["bne",        _rw2,                         _id]);
        // NOW safe to switch $D016 to HR fine scroll — we are on the scroll row
        array_push(_list, ["lda_imm",   0xC8,                           _id]); // 40-col base, HR
        array_push(_list, ["and_imm",   0xF0,                           _id]);
        array_push(_list, ["ora_lab",   _v_dir,                         _id]);
        array_push(_list, ["sta_abs",   0xD016,                         _id]);
        // Wait for end of scroll row
        var _rw3 = _p + "rw3";
        array_push(_list, ["lda_imm",    (_raster + 8) & 0xFF,         _id]);
        array_push(_list, ["label",      _rw3]);
        array_push(_list, ["cmp_abs",    0xD012,                       _id]);
        array_push(_list, ["bne",        _rw3,                         _id]);
        // POST-NOP Delay
        repeat(_post_nop) { array_push(_list, ["nop", 0, _id]); }
		
// Restore $DD00 and $D018 first — bank and charset pointer
        array_push(_list, ["lda_lab",   _v_dd00,                        _id]);
        array_push(_list, ["sta_abs",   0xDD00,                         _id]);
        array_push(_list, ["lda_lab",   _v_d018,                        _id]);
        array_push(_list, ["sta_abs",   0xD018,                         _id]);
        array_push(_list, ["lda_lab",   _v_d011,                        _id]);
        array_push(_list, ["sta_abs",   0xD011,                         _id]);
        // Restore $D016 last — fine scroll=7 (no scroll active) + MC bit from map mode
        //array_push(_list, ["lda_imm",   0xC8 | (_ts_map_mode << 4),    _id]);
        //array_push(_list, ["and_imm",   0xF0,                           _id]);
        //array_push(_list, ["ora_imm",   0x07,                           _id]);
        //array_push(_list, ["sta_abs",   0xD016,                         _id]);
		
		// Restore $D016 — use saved value to preserve Multicolor/40-col mode, but reset fine scroll to 7
        array_push(_list, ["lda_lab",   _v_d016,                        _id]);
        array_push(_list, ["and_imm",   0xF8,                           _id]); // Keep bits 7-3 (Mode/Width)
        array_push(_list, ["ora_imm",   0x07,                           _id]); // Force bits 2-0 to 7 (No scroll)
        array_push(_list, ["sta_abs",   0xD016,                         _id]);
		
        // Repoint back to sid_irq
        array_push(_list, ["lda_lab_lo", "sid_irq",                     _id]);
        array_push(_list, ["sta_abs",    0x0314,                       _id]);
        array_push(_list, ["lda_lab_hi", "sid_irq",                     _id]);
        array_push(_list, ["sta_abs",    0x0315,                       _id]);
        array_push(_list, ["lda_imm",    global.sid_irq_line,          _id]);
        array_push(_list, ["sta_abs",    0xD012,                       _id]);
        array_push(_list, ["pla",        0,                            _id]);
        array_push(_list, ["tay",        0,                            _id]);
        array_push(_list, ["pla",        0,                            _id]);
        array_push(_list, ["tax",        0,                            _id]);
        array_push(_list, ["pla",        0,                            _id]);
        array_push(_list, ["rti",        0,                            _id]);

    }

array_push(_list, ["label",   _SINIT]);
    // Clear scroll row in screen RAM to spaces
    var _clr = _p + "clr";
    array_push(_list, ["lda_imm", 0x20,         _id]);
    array_push(_list, ["ldx_imm", 0x27,         _id]);
    array_push(_list, ["label",   _clr              ]);
    array_push(_list, ["sta_abx", _scr_row,     _id]);
    array_push(_list, ["dex",     0,            _id]);
    array_push(_list, ["bpl",     _clr,         _id]);
    array_push(_list, ["lda_imm", _txt_addr & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0x02,                    _id]);
	array_push(_list, ["lda_imm", (_txt_addr >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0x03,                    _id]);
    array_push(_list, ["lda_imm", _colour,                 _id]);
    array_push(_list, ["sta_lab", _v_colour,               _id]);
    array_push(_list, ["lda_imm", _speed,                  _id]);
    array_push(_list, ["sta_lab", _v_speed0,               _id]);
    array_push(_list, ["lda_imm", 7,                       _id]);  // always start left
    array_push(_list, ["sta_lab", _v_dir,                  _id]);
    array_push(_list, ["rts",     0,                       _id]);

    // ════════════════════════════════════════════════════════
    // Scroller subroutine
    // ════════════════════════════════════════════════════════
    var _nopause  = _p + "nopause";
    var _morewait = _p + "morewait";
    var _nocarry  = _p + "nocarry";
    var _lp        = _p + "lp";
    var _tps       = _p + "tps";
    var _nospd    = _p + "nospd";
    var _nocol    = _p + "nocol";
    var _nopau    = _p + "nopau";
    var _notdone  = _p + "notdone";
    var _nochar   = _p + "nochar";
    var _noc      = _p + "noc";

// JSR MODE wrapper — sits between _SINIT and _SCRL
    if (_jsr_mode == 1) {
        array_push(_list, ["label",   _p + "scrl"]);
        array_push(_list, ["lda_lab", _v_flag,         _id]);
        array_push(_list, ["beq",     _p + "scrldone", _id]);
        array_push(_list, ["lda_imm", 0x00,            _id]);
        array_push(_list, ["sta_lab", _v_flag,          _id]);
        array_push(_list, ["jsr",     _SCRL,            _id]);
        array_push(_list, ["label",   _p + "scrldone"]);
        array_push(_list, ["rts",     0,                _id]);
    }

    array_push(_list, ["label",   _SCRL]);

    // Pause check
    array_push(_list, ["lda_lab", _v_pause,  _id]);
    array_push(_list, ["beq",     _nopause,  _id]);
    array_push(_list, ["inc_lab", _v_waitc,  _id]);
    array_push(_list, ["lda_lab", _v_waitc,  _id]);
    array_push(_list, ["cmp_imm", 0x50,      _id]);
    array_push(_list, ["bne",     _morewait, _id]);
    array_push(_list, ["lda_imm", 0x00,      _id]);
    array_push(_list, ["sta_lab", _v_pause,  _id]);
    array_push(_list, ["sta_lab", _v_waitc,  _id]);
    array_push(_list, ["lda_lab", _v_speed1, _id]);
    array_push(_list, ["sta_lab", _v_speed0, _id]);
    array_push(_list, ["label",   _morewait]);
    array_push(_list, ["rts",     _tps,         _id]);

    // Fine scroll tick
    array_push(_list, ["label",   _nopause]);
    array_push(_list, ["lda_lab", _v_dir,    _id]);
    array_push(_list, ["sec",     0,         _id]);
    array_push(_list, ["sbc_lab", _v_speed0, _id]);
    array_push(_list, ["and_imm", 0x07,      _id]);
    array_push(_list, ["sta_lab", _v_dir,    _id]);
    array_push(_list, ["bcc",     _nocarry,  _id]);
    array_push(_list, ["rts",     _tps,         _id]);

    // Column shift
    array_push(_list, ["label",   _nocarry]);
    array_push(_list, ["ldx_imm", 0x00,         _id]);
    array_push(_list, ["label",   _lp]);
    array_push(_list, ["lda_abx", _scr_row + 1, _id]);
    array_push(_list, ["sta_abx", _scr_row,     _id]);
    array_push(_list, ["lda_abx", _col_row + 1, _id]);
    array_push(_list, ["sta_abx", _col_row,     _id]);
    array_push(_list, ["inx",     0,            _id]);
    array_push(_list, ["cpx_imm", 0x27,         _id]);
    array_push(_list, ["bne",     _lp,          _id]);

    // Fetch & decode char
    array_push(_list, ["label",   _tps]);
    array_push(_list, ["ldy_imm", 0x00,      _id]);
    array_push(_list, ["lda_izy", 0x02,      _id]);
    array_push(_list, ["sta_lab", _v_saveA,  _id]);

    // speed cmd $F9-$FF
    array_push(_list, ["cmp_imm", 0xF9,      _id]);
    array_push(_list, ["bcc",     _nospd,    _id]);
    array_push(_list, ["and_imm", 0x07,      _id]);
    array_push(_list, ["sta_lab", _v_speed0, _id]);
    // FIX: Advance pointer and fetch next char immediately
    array_push(_list, ["jsr",     _p + "adv_ptr", _id]);
    array_push(_list, ["jmp",     _tps,      _id]);

    // colour cmd $E0-$EF
    array_push(_list, ["label",   _nospd]);
    array_push(_list, ["lda_lab", _v_saveA,  _id]);
    array_push(_list, ["cmp_imm", 0xE0,      _id]);
    array_push(_list, ["bcc",     _nocol,    _id]);
    if (_ts_map_mode == 1) {
        array_push(_list, ["and_imm", 0x07,      _id]); // Mask to base colour (0-7)
        array_push(_list, ["ora_imm", 0x08,      _id]); // Force MC bit 3 on
    } else {
        array_push(_list, ["and_imm", 0x0F,      _id]); // Standard HR colour
    }
    array_push(_list, ["sta_lab", _v_colour, _id]);
    // FIX: Advance pointer and fetch next char immediately
    array_push(_list, ["jsr",     _p + "adv_ptr", _id]);
    array_push(_list, ["jmp",     _tps,      _id]);

    // track cmd $D0-$DE  (#/trk00-#/trk14)
    var _notrk = _p + "notrk";
    array_push(_list, ["label",   _nocol]);
    array_push(_list, ["lda_lab", _v_saveA,  _id]);
    array_push(_list, ["cmp_imm", 0xD0,      _id]);
    array_push(_list, ["bcc",     _notrk,    _id]);
    array_push(_list, ["cmp_imm", 0xDF,      _id]);
    array_push(_list, ["bcs",     _notrk,    _id]);
    array_push(_list, ["and_imm", 0x0F,      _id]);
    array_push(_list, ["jsr",     "sid_init_entry", _id]);
    // FIX: Advance pointer and fetch next char immediately
    array_push(_list, ["jsr",     _p + "adv_ptr", _id]);
    array_push(_list, ["jmp",     _tps,      _id]);

    // pause cmd $DF
    array_push(_list, ["label",   _notrk]);
    array_push(_list, ["lda_lab", _v_saveA,  _id]);
    array_push(_list, ["cmp_imm", 0xDF,      _id]);
    array_push(_list, ["bne",     _nopau,    _id]);
	
    array_push(_list, ["lda_imm", 0x01,      _id]);
    array_push(_list, ["sta_lab", _v_pause,  _id]);
    array_push(_list, ["lda_lab", _v_speed0, _id]);
    array_push(_list, ["sta_lab", _v_speed1, _id]);
    array_push(_list, ["lda_imm", 0x00,      _id]);
    array_push(_list, ["sta_lab", _v_speed0, _id]);
    // FIX: Advance pointer and fetch next char immediately
    array_push(_list, ["jsr",     _p + "adv_ptr", _id]);
    array_push(_list, ["jmp",     _tps,      _id]);

    // null = restart
    array_push(_list, ["label",   _nopau]);
    array_push(_list, ["lda_lab", _v_saveA,  _id]);
    array_push(_list, ["bne",     _notdone,  _id]);
    array_push(_list, ["lda_imm", _txt_addr & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0x02,      _id]);
    array_push(_list, ["lda_imm", (_txt_addr >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0x03,      _id]);
    array_push(_list, ["jmp",     _tps,      _id]);

    // Write char + colour
    array_push(_list, ["label",   _notdone]);
    array_push(_list, ["sta_abs", _scr_row + 0x27, _id]);
    array_push(_list, ["lda_lab", _v_colour,       _id]);
    array_push(_list, ["sta_abs", _col_row + 0x27, _id]);

    // Advance pointer
    array_push(_list, ["label",   _nochar]);
    array_push(_list, ["label",   _p + "adv_ptr"]); // Shared label for logic jumps
    array_push(_list, ["clc",     0,         _id]);
    array_push(_list, ["lda_zp",  0x02,      _id]);
    array_push(_list, ["adc_imm", 0x01,      _id]);
    array_push(_list, ["sta_zp",  0x02,      _id]);
    array_push(_list, ["bcc",     _noc,      _id]);
    array_push(_list, ["inc_zp",  0x03,      _id]);
    array_push(_list, ["label",   _noc]);
    array_push(_list, ["rts",     _tps,         _id]);

    // Variable storage
    array_push(_list, ["label",   _v_flag]);   array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_saveA]);  array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_saveX]);  array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_saveY]);  array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_colour]); array_push(_list, ["byte", _colour, _id]);
    array_push(_list, ["label",   _v_dir]);    array_push(_list, ["byte", _dir,    _id]);
    array_push(_list, ["label",   _v_waitc]);  array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_pause]);  array_push(_list, ["byte", 0x00,    _id]);
    array_push(_list, ["label",   _v_speed0]); array_push(_list, ["byte", _speed,  _id]);
    array_push(_list, ["label",   _v_speed1]); array_push(_list, ["byte", 0x00,    _id]);
array_push(_list, ["label",   _v_d011]);   array_push(_list, ["byte", 0x1B,     _id]);
    array_push(_list, ["label",   _v_d016]);   array_push(_list, ["byte", _ts_d016, _id]);
    array_push(_list, ["label",   _v_d018]);   array_push(_list, ["byte", 0x80,    _id]);
array_push(_list, ["label",   _v_dd00]);   array_push(_list, ["byte", 0x02,    _id]);

    // JSR MODE: spine resumes here after all subroutines
    if (_jsr_mode == 1) {
        array_push(_list, ["label",   _SKIP]);
    }

// Text data at _txt_addr
	array_push(_list, ["org",   -2]);
    array_push(_list, ["org",   _txt_addr]);
    array_push(_list, ["label", _p + "dat"]);
    var _id_save = _id;
    var _id = noone;  // suppress node tagging for text data bytes

	_txt_str = string_replace_all(_txt_str, "\n", "");
	_txt_str = string_replace_all(_txt_str, "\r", "");
    var _si = 1;
    while (_si <= string_length(_txt_str)) {
        if (string_copy(_txt_str, _si, 1) == "_") {
            var _cmd = string_copy(_txt_str, _si, 7);
            var _matched = false;
            // _spd01 - _spd07
            if (string_copy(_cmd, 1, 4) == "_spd") {
                var _sn = string_copy(_txt_str, _si + 4, 2);
                if (string_digits(_sn) == _sn && string_length(_sn) == 2) {
                    array_push(_list, ["byte", 0xF8 + clamp(real(_sn), 1, 7), _id]);
                    _si += 6; _matched = true;
                }
            }
            // _col00 - _col15
            if (!_matched && string_copy(_cmd, 1, 4) == "_col") {
                var _cn = string_copy(_txt_str, _si + 4, 2);
                if (string_digits(_cn) == _cn && string_length(_cn) == 2) {
                    array_push(_list, ["byte", 0xE0 + clamp(real(_cn), 0, 15), _id]);
                    _si += 6; _matched = true;
                }
            }
            // _wait
            if (!_matched && string_copy(_txt_str, _si, 5) == "_wait") {
                array_push(_list, ["byte", 0xDF, _id]);
                _si += 5; _matched = true;
            }
            // _trk00 - _trk14
            if (!_matched && string_copy(_txt_str, _si, 4) == "_trk") {
                var _tn = string_copy(_txt_str, _si + 4, 2);
                if (string_digits(_tn) == _tn && string_length(_tn) == 2) {
                    array_push(_list, ["byte", 0xD0 + clamp(real(_tn), 0, 14), _id]);
                    _si += 6; _matched = true;
                }
            }
            show_debug_message("CMD matched: " + _cmd + " si now=" + string(_si));
            if (_matched) continue;
        }


// Normal char -> screencode [Expanded Set]
        var _b = string_ord_at(_txt_str, _si);
        
        if (_b >= 65 && _b <= 90) { 
            _b -= 64; // A-Z (Upper)
        } 
        else if (_b >= 97 && _b <= 122) { 
            _b -= 96; // a-z (Lower to Upper)
        } 
        else if (_b == 163 || _b == 100) { 
            _b = 28;  // £ (Pound Symbol) mapping
        } 
        else if (_b >= 32 && _b <= 64) { 
            _b = _b;  // Pass-through: Space, !, ", #, $, %, &, ', (, ), *, +, ,, -, ., /, 0-9, :, ;, <, =, >, ?, @
        } 
        else if (_b >= 91 && _b <= 95) {
            _b = _b;  // Pass-through: [, \, ], ^, _
        }
        
	array_push(_list, ["byte", _b]);  // no node tag — lives at _txt_addr, not in code block
        _si++;
    }
    array_push(_list, ["byte", 0x00]);  // no node tag
    array_push(_list, ["org",  -3]);
    var _id = _id_save;  // restore

} break;

// --------------------------------------------------------
// MACRO_JOY
// Reads a CIA joystick port, dispatches via AND/BNE to JMP targets.
// --------------------------------------------------------
case "MACRO_JOY": {
	var _id        = _curr;
	var _port      = is_real(_id.instructions[0][1]) ? real(_id.instructions[0][1]) : 2;
	var _state_zp  = is_real(_id.instructions[0][2]) ? real(_id.instructions[0][2]) : 0xF8;
	var _port_addr = (_port == 1) ? 0xDC01 : 0xDC00;
	var _flag_zp   = 0xFB;

	array_push(_list, ["lda_zp",  _flag_zp,   _id]);
	array_push(_list, ["bne",     "joy_read",  _id]);
	array_push(_list, ["lda_imm", 0x01,        _id]);
	array_push(_list, ["sta_zp",  _flag_zp,    _id]);

	array_push(_list, ["label",   "joy_read"      ]);
	array_push(_list, ["lda_abs", _port_addr,  _id]);
	array_push(_list, ["cmp_abs", _port_addr,  _id]);
	array_push(_list, ["bne",     "joy_read",  _id]);
	array_push(_list, ["sta_zp",  _state_zp,   _id]);

	var _non_target  = "";
	var _non_enabled = false;
	for (var _i = 1; _i < array_length(_id.instructions); _i++) {
		var _row     = _id.instructions[_i];
		var _mask    = is_real(_row[0]) ? real(_row[0]) : 0xFF;
		var _target  = _row[1];
		var _enabled = (_row[2] == 1);
		if (_enabled == false) { continue; }
		if (_mask == 0xFF) {
		    _non_target  = _target;
		    _non_enabled = true;
		    continue;
		}
		var _skip_lbl = "joy_skip_" + string(_i) + "_" + string(real(_id));
		array_push(_list, ["lda_zp",  _state_zp,  _id]);
		array_push(_list, ["and_imm", _mask,       _id]);
		array_push(_list, ["bne",     _skip_lbl,   _id]);
		array_push(_list, ["jsr",     _target,     _id]);
		array_push(_list, ["jmp",     "joy_done",  _id]);
		array_push(_list, ["label",   _skip_lbl        ]);
	}
	if (_non_enabled) {
	    array_push(_list, ["jsr", _non_target, _id]);
	}
	array_push(_list, ["label", "joy_done"]);
} break;

// --------------------------------------------------------
// MACRO_LOADER
// Loads one file from a LOAD_ORG D64 on demand.
// Uses KERNAL: SETLFS / SETNAM / LOAD with secondary $01
// so the file loads to its embedded PRG header address.
// Layout: instructions[0] = [
//   "macro_loader",
//   org_name,     // LOAD_ORG asset name
//   file_name,    // linked asset name
//   mode          // reserved for future override (0 = use header addr)
// ]
// --------------------------------------------------------
case "MACRO_LOADER": {
    var _id        = _curr;
    var _org_name  = (array_length(_id.instructions[0]) > 1) ? string(_id.instructions[0][1]) : "";
    var _file_name = (array_length(_id.instructions[0]) > 2) ? string(_id.instructions[0][2]) : "";

    if (_org_name == "" || _file_name == "") {
        show_debug_message("MACRO_LOADER WARNING: org=[" + _org_name + "] file=[" + _file_name + "] — incomplete, skipping emit");
        break;
    }

    // Resolve d64_filename from the LOAD_ORG's linked_assets
    var _d64_filename = "";
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "LOAD_ORG" && _a.name == _org_name) {
                if (variable_struct_exists(_a, "linked_assets")) {
                    var _lks = _a.linked_assets;
                    for (var _lki = 0; _lki < array_length(_lks); _lki++) {
                        if (_lks[_lki].asset_name == _file_name) {
                            _d64_filename = variable_struct_exists(_lks[_lki], "d64_filename")
                                          ? _lks[_lki].d64_filename : string_upper(_file_name);
                            break;
                        }
                    }
                }
                break;
            }
        }
    }
    if (_d64_filename == "") {
        show_debug_message("MACRO_LOADER WARNING: '" + _file_name + "' not linked to LOAD_ORG '" + _org_name + "'");
        break;
    }

    // Pad/clip to PETSCII uppercase, max 16 chars
    _d64_filename = string_upper(_d64_filename);
    if (string_length(_d64_filename) > 16) {
        _d64_filename = string_copy(_d64_filename, 1, 16);
    }
    var _fn_len = string_length(_d64_filename);

    var _p          = "ldr" + string(real(_id)) + "_";
    var _lbl_skip   = _p + "skip";
    var _lbl_fname  = _p + "fname";

    show_debug_message("MACRO_LOADER: org=" + _org_name + " file=" + _file_name
        + " d64=" + _d64_filename + " len=" + string(_fn_len));

    // Filename table — jumped over at runtime
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);
    array_push(_list, ["label",   _lbl_fname]);
    for (var _si = 1; _si <= _fn_len; _si++) {
        var _ch = string_ord_at(_d64_filename, _si);
        // PETSCII pass-through — d64 names are already in PETSCII range
        array_push(_list, ["byte", _ch & 0xFF, _id]);
    }
    array_push(_list, ["label", _lbl_skip]);

    // SETLFS — logical file 1, device 8, secondary 1 (use header load addr)
    array_push(_list, ["lda_imm", 0x01,   _id]);
    array_push(_list, ["ldx_imm", 0x08,   _id]);
    array_push(_list, ["ldy_imm", 0x01,   _id]);
    array_push(_list, ["jsr",     0xFFBA, _id]); // SETLFS

    // SETNAM — A = filename length, X/Y = filename pointer
    array_push(_list, ["lda_imm",    _fn_len,    _id]);
    array_push(_list, ["ldx_lab_lo", _lbl_fname, _id]);
    array_push(_list, ["ldy_lab_hi", _lbl_fname, _id]);
    array_push(_list, ["jsr",        0xFFBD,     _id]); // SETNAM

    // LOAD — A = 0 (load, not verify); X/Y ignored when secondary = 1
    array_push(_list, ["lda_imm", 0x00,   _id]);
    array_push(_list, ["ldx_imm", 0x00,   _id]);
    array_push(_list, ["ldy_imm", 0x00,   _id]);
    array_push(_list, ["jsr",     0xFFD5, _id]); // LOAD
} break;


case "MACRO_LOAD_GAME": scr_compile_macro_load_game(_list, _curr); break;
case "MACRO_SAVE_GAME": scr_compile_macro_save_game(_list, _curr); break;

// --------------------------------------------------------
// MACRO_TRACK
// Runtime track switcher - polls GETIN each frame.
// SEI/CLI guards prevent IRQ firing mid-init or mid-GETIN.
// sid_getin label must resolve to $FFE4 at build time.
// --------------------------------------------------------
case "MACRO_TRACK": {
    var _id    = _curr;
    var _track = is_real(_curr.instructions[0][1]) ? real(_curr.instructions[0][1]) : 0;
    array_push(_list, ["lda_imm", _track, _id]);
    array_push(_list, ["jsr",     "sid_init_entry", _id]);
} break;

// --------------------------------------------------------
// MACRO_SID
// Full SID music setup with raster IRQ.
// --------------------------------------------------------
case "MACRO_SID": {
	// Temporarily add at the top of the MACRO_SID case in scr_compile_chain:

	    var _id      = _curr;
	    var _track   = is_real(_curr.instructions[0][2]) ? clamp(real(_curr.instructions[0][2]), 0, 31) : 0;
	    var _volume  = is_real(_curr.instructions[0][3]) ? clamp(real(_curr.instructions[0][3]), 0, 15) : 12;
		var _irq_line = (array_length(_curr.instructions[0]) > 4 && is_real(_curr.instructions[0][4])) ? clamp(real(_curr.instructions[0][4]), 0, 255) : global.sid_irq_line;

		var _sid_addr   = 0x1000;
	    var _init_addr  = 0x1000;
	    var _play_addr  = 0x1003;
	    var _asset_name = string(_curr.instructions[0][1]);
        var _found_valid_sid = false;
if (instance_exists(obj_asset_manager)) {
	        var _am = obj_asset_manager;
	        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	            var _a = ds_list_find_value(_am.asset_list, _ai);
	            if ((_a.type == "SID_MUSIC" || _a.type == "SID_SFX") &&
	                (_a.name == _asset_name || (_asset_name == "" && !_found_valid_sid))) {
	                _sid_addr  = _a.address;
	                _init_addr = variable_struct_exists(_a.meta, "sid_init_addr") ? real(_a.meta.sid_init_addr) : _a.address;
	                _play_addr = variable_struct_exists(_a.meta, "sid_play_addr") ? real(_a.meta.sid_play_addr) : _a.address + 3;
	                _found_valid_sid = true;
	                if (_a.name == _asset_name) break; // exact match — stop here
	            }
	        }
	    }
if (!_found_valid_sid) {
            global.inject_null_sid = true;
            // Fallback: use first available SID asset
            if (instance_exists(obj_asset_manager)) {
                var _am = obj_asset_manager;
                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                    var _a = ds_list_find_value(_am.asset_list, _ai);
                    if (_a.type == "SID_MUSIC" || _a.type == "SID_SFX") {
                        _sid_addr  = _a.address;
                        _init_addr = variable_struct_exists(_a.meta, "sid_init_addr") ? real(_a.meta.sid_init_addr) : _a.address;
                        _play_addr = variable_struct_exists(_a.meta, "sid_play_addr") ? real(_a.meta.sid_play_addr) : _a.address + 3;
                        _found_valid_sid = true;
                        global.inject_null_sid = false;
                        show_debug_message("SID fallback found: " + _a.name + " inject_null_sid=" + string(global.inject_null_sid));
                        break;
                    }
                }
            }
        }

	    // --- Volume + SID clear --- (identical to your working version)
	    array_push(_list, ["lda_imm",  _volume, _id]);
	    array_push(_list, ["sta_abs",  0xD418,  _id]);
	    array_push(_list, ["lda_imm",  0x00,    _id]);
	    array_push(_list, ["ldx_imm",  24,      _id]);
	    array_push(_list, ["label",    "sid_clear"   ]);
	    array_push(_list, ["sta_abx",  0xD400,  _id]);
	    array_push(_list, ["dex",      0,       _id]);
	    array_push(_list, ["bpl",      "sid_clear", _id]);

// --- Init default track ---
    array_push(_list, ["lda_imm",  0x37,            _id]);
    array_push(_list, ["sta_zp",   0x01,            _id]);
    array_push(_list, ["lda_imm",  _track,          _id]);
    array_push(_list, ["ldx_imm",  0,               _id]);
    array_push(_list, ["ldy_imm",  0,               _id]);
	array_push(_list, ["jsr",      real(_init_addr), _id]);
    // Raw INS2SND2 SFX needs no init — sfx_play subroutine emitted by MACRO_SFX
    var _sfx_init_addr = 0; // kept for IRQ tick check below

 // --- Hook IRQ vector — only if no MACRO_IRQ_HANDLER present ---
    var _has_irq_handler_compile = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ_HANDLER" && is_connected && org_parent == noone)
            { _has_irq_handler_compile = true; break; }
    }
    if (!_has_irq_handler_compile) {
        array_push(_list, ["sei",     0,      _id]);
        array_push(_list, ["lda_imm", 0xAA,   _id]);
        array_push(_list, ["sta_abs", 0x0314, _id]);
        array_push(_list, ["lda_imm", 0xBB,   _id]);
        array_push(_list, ["sta_abs", 0x0315, _id]);
        array_push(_list, ["lda_imm", 0x7B,   _id]);
        array_push(_list, ["sta_abs", 0xDC0D, _id]);
        array_push(_list, ["lda_abs", 0xD011, _id]);
        array_push(_list, ["and_imm", 0x7F,   _id]);
        array_push(_list, ["sta_abs", 0xD011, _id]);
        array_push(_list, ["lda_imm", _irq_line, _id]);
        array_push(_list, ["sta_abs", 0xD012, _id]);
        array_push(_list, ["lda_imm", 0xFF,   _id]);
        array_push(_list, ["sta_abs", 0xD019, _id]);
        array_push(_list, ["lda_imm", 0x81,   _id]);
        array_push(_list, ["sta_abs", 0xD01A, _id]);
        array_push(_list, ["cli",     0,      _id]);
    }

// --- Main loop ---
	    array_push(_list, ["label",   "sid_main_loop"    ]);
	    var _jump_target = "sid_main_loop";
	    var _best_y_sid  = 999999;
	    var _found_sid   = noone;
	    var _curr_ref    = _curr;
	    with (obj_c64_node) {
            // Using y >= _curr_ref.y + 1 to catch labels on the same line or below, 
            // while excluding the MACRO_SID node itself.
	        if (is_connected && org_parent == noone && y >= (_curr_ref.y + 1) && y < _best_y_sid && node_type == "LABEL") {
	            _best_y_sid = y;
	            _found_sid  = id;
	        }

			

			
			
	    }
	    if (instance_exists(_found_sid)) {
	        _jump_target = string_replace_all(string(_found_sid.instructions[0][1]), " ", "_");
	    }
	    array_push(_list, ["jmp", _jump_target, _id]);

	    // Pre-compute IRQ node presence before sid_irq handler
		var _has_irq_nodes = false;
		var _first_irq_handler_label = "";
		var _first_irq_raster = 0x3C;
		with (obj_c64_node) {
		    if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone) {
		        _has_irq_nodes = true;
		        var _irq_nodes2 = [];
		        with (obj_c64_node) {
		            if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
		                array_push(_irq_nodes2, id);
		        }
		        array_sort(_irq_nodes2, function(_a, _b) {
		            var _ra = (array_length(_a.instructions[0]) > 1 && is_real(_a.instructions[0][1])) ? real(_a.instructions[0][1]) : 0x3C;
		            var _rb = (array_length(_b.instructions[0]) > 1 && is_real(_b.instructions[0][1])) ? real(_b.instructions[0][1]) : 0x3C;
		            return _ra - _rb;
		        });
		        var _fn = _irq_nodes2[0];
		        _first_irq_handler_label = "irq" + string(real(_fn)) + "_handler";
		        _first_irq_raster = (array_length(_fn.instructions[0]) > 1 && is_real(_fn.instructions[0][1])) ? clamp(real(_fn.instructions[0][1]), 0, 255) : 0x3C;
		        break;
		    }
		}

	    // --- IRQ handler ---
		if (!_has_irq_handler_compile) {
    array_push(_list, ["label",   "sid_irq"          ]);
		array_push(_list, ["lda_zp",   0x01,     _id]);   // [FIX-$01] save current banking state
		array_push(_list, ["pha",      0,        _id]);    // [FIX-$01] push to stack before overwriting
		array_push(_list, ["lda_imm",  0x37,     _id]);
		array_push(_list, ["sta_zp",   0x01,     _id]);
		if (!_has_irq_nodes) {
		    array_push(_list, ["lda_abs",  0xDC0D,   _id]);
		}
		array_push(_list, ["lda_abs",  0xD019,   _id]);
		array_push(_list, ["sta_abs",  0xD019,   _id]);
		array_push(_list, ["jsr",      real(_play_addr), _id]);


			with (obj_c64_node) {
		    if (node_type == "MACRO_TEXT_SCROLL" && is_connected) {
		        var _saved_alias_sid = (array_length(id.instructions[0]) > 12 && is_string(id.instructions[0][12]) && string(id.instructions[0][12]) != "") ? string(id.instructions[0][12]) : "";
        if (string_pos("ts", _saved_alias_sid) == 1) {
            var _sfx2 = string_copy(_saved_alias_sid, 3, string_length(_saved_alias_sid) - 2);
            if (string_digits(_sfx2) == _sfx2 && string_length(_sfx2) > 3) _saved_alias_sid = "";
        }
        var _hook_p = (_saved_alias_sid != "") ? (_saved_alias_sid + "_") : ("ts" + string(real(id)) + "_");
		        var _scroll_raster = clamp(50 + (clamp(real(id.instructions[0][1]), 0, 24) * 8) -1, 0, 255); // EDIT for early the -1
show_debug_message("SID raster-chain to: [" + _hook_p + "scroll] raster=$" + string_upper(decimal_to_hex(_scroll_raster)));				
		        show_debug_message("SID scroll hook: _hook_p=[" + _hook_p + "] full label=[" + _hook_p + "scroll]");
		        array_push(_list, ["lda_lab_lo", _hook_p + "scroll", _id]);				 
		        array_push(_list, ["sta_abs",    0x0314,              _id]);
		        array_push(_list, ["lda_lab_hi", _hook_p + "scroll", _id]);
		        array_push(_list, ["sta_abs",    0x0315,              _id]);
		        array_push(_list, ["lda_imm",    _scroll_raster,      _id]);
		        array_push(_list, ["sta_abs",    0xD012,              _id]);
		        break;
		    }
		}


if (_has_irq_nodes) {
		    // JSR to each MACRO_IRQ handler in raster order — they end with RTS
		    var _irq_sorted = [];
		    with (obj_c64_node) {
		        if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
		            array_push(_irq_sorted, id);
		    }
		    array_sort(_irq_sorted, function(_a, _b) {
		        var _ra = (array_length(_a.instructions[0]) > 1 && is_real(_a.instructions[0][1])) ? real(_a.instructions[0][1]) : 0x60;
		        var _rb = (array_length(_b.instructions[0]) > 1 && is_real(_b.instructions[0][1])) ? real(_b.instructions[0][1]) : 0x60;
		        return _ra - _rb;
		    });
		    for (var _ii = 0; _ii < array_length(_irq_sorted); _ii++) {
		        var _irq_n = _irq_sorted[_ii];
		        var _irq_lbl = "irq" + string(real(_irq_n)) + "_handler";
		        array_push(_list, ["jsr", _irq_lbl, _id]);
		    }
		} else {
		    array_push(_list, ["jsr", 0xEA87, _id]);
		}

		array_push(_list, ["pla",      0,        _id]);   // [FIX-$01] pop saved $01 value
		array_push(_list, ["sta_zp",   0x01,     _id]);   // [FIX-$01] restore original banking state
		array_push(_list, ["pla",      0,        _id]);
		array_push(_list, ["tay",      0,        _id]);
		array_push(_list, ["pla",      0,        _id]);
		array_push(_list, ["tax",      0,        _id]);
		array_push(_list, ["pla",      0,        _id]);
		array_push(_list, ["rti",      0,        _id]);
	    // --- sid_init_entry subroutine ---
	    // Sits after RTI so it is never reached by fall-through.
	    // MACRO_TRACK calls this with track number in A.
	    // Owns SEI/CLI and banking internally.
	    } // end !_has_irq_handler_compile
	    // --- sid_init_entry subroutine ---
	    array_push(_list, ["label",   "sid_init_entry"           ]);
	    array_push(_list, ["sta_zp",  0xFE,              _id]);   // stash track number
	    array_push(_list, ["sei",     0,                 _id]);
	    array_push(_list, ["lda_imm", 0x37,              _id]);
	    array_push(_list, ["sta_zp",  0x01,              _id]);
	    array_push(_list, ["lda_imm", 0xFF,              _id]);
	    array_push(_list, ["sta_abs", 0xD019,            _id]);   // clear pending VIC IRQ
	    array_push(_list, ["lda_zp",  0xFE,              _id]);   // restore track to A
	    array_push(_list, ["ldx_imm", 0,                 _id]);
	    array_push(_list, ["ldy_imm", 0,                 _id]);
	    array_push(_list, ["jsr",     real(_init_addr),  _id]);
	    array_push(_list, ["lda_imm", 0x37,              _id]);
	    array_push(_list, ["sta_zp",  0x01,              _id]);
	    array_push(_list, ["cli",     0,                 _id]);
	    array_push(_list, ["rts",     0,                 _id]);
	} break;

// --------------------------------------------------------
// MACRO_SFX compile chain case
// --------------------------------------------------------
case "MACRO_SFX": {
    var _id         = _curr;
    var _asset_name = string(_curr.instructions[0][1]);
    var _sfx_index  = (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2]))
                    ? clamp(real(_curr.instructions[0][2]), 0, 63) : 0;
    var _voice      = (array_length(_curr.instructions[0]) > 3 && is_real(_curr.instructions[0][3]))
                    ? clamp(real(_curr.instructions[0][3]), 1, 3) : 3;

    var _gt_channel = (_voice - 1) * 7;

    var _sfx_entry = 0x1006;
	
    //if (instance_exists(obj_asset_manager)) {
    //    var _am = obj_asset_manager;
    //    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
    //        var _a = ds_list_find_value(_am.asset_list, _ai);
    //        if (_a.type == "SID_MUSIC" && variable_struct_exists(_a.meta, "sid_play_addr")) {
    //           _sfx_entry = real(_a.meta.sid_play_addr) + 3;
	//		break;
    //        }
    //    }
    //}
	
	   if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SID_MUSIC") {
                _sfx_entry = _a.address + 6; // always load_addr+6, independent of play addr
                break;
            }
        }
    }
	

var _lbl_blob = "sfxdata_" + _asset_name + "_" + string(_sfx_index);

// Check if this SFX asset is load_org_linked — if so, calculate fixed address
// instead of using a label (the label won't exist as data is on disk not in PRG)
var _sfx_is_disk = false;
var _sfx_blob_addr = 0;
if (instance_exists(obj_asset_manager)) {
    var _am_sfx = obj_asset_manager;
    for (var _loi2 = 0; _loi2 < ds_list_size(_am_sfx.asset_list); _loi2++) {
        var _loa2 = ds_list_find_value(_am_sfx.asset_list, _loi2);
        if (_loa2.type != "LOAD_ORG") continue;
        if (!variable_struct_exists(_loa2, "linked_assets")) continue;
        for (var _loli2 = 0; _loli2 < array_length(_loa2.linked_assets); _loli2++) {
            var _lolink2 = _loa2.linked_assets[_loli2];
            if (variable_struct_exists(_lolink2, "asset_name") && _lolink2.asset_name == _asset_name) {
                _sfx_is_disk = true;
                break;
            }
        }
        if (_sfx_is_disk) break;
    }
}

if (_sfx_is_disk) {
    // Find the asset and calculate the blob address by summing instrument sizes
    if (instance_exists(obj_asset_manager)) {
        var _am_sfx2 = obj_asset_manager;
        for (var _ai2 = 0; _ai2 < ds_list_size(_am_sfx2.asset_list); _ai2++) {
            var _a2 = ds_list_find_value(_am_sfx2.asset_list, _ai2);
            if (_a2.type != "SFX_DATA" || _a2.name != _asset_name) continue;
            _sfx_blob_addr = _a2.address;
            var _instrs2 = variable_struct_exists(_a2.meta, "instruments") ? _a2.meta.instruments : [];
            for (var _ii2 = 0; _ii2 < _sfx_index; _ii2++) {
                if (_ii2 < array_length(_instrs2)) {
                    _sfx_blob_addr += 3 + array_length(_instrs2[_ii2].wavetable_rows) * 2;
                }
            }
            break;
        }
    }
}

show_debug_message("MACRO_SFX: asset=" + _asset_name + " sfx_entry=$" + string_upper(decimal_to_hex(_sfx_entry)) + " blob=" + _lbl_blob + " disk=" + string(_sfx_is_disk) + " blob_addr=$" + string_upper(decimal_to_hex(_sfx_blob_addr)) + " channel=" + string(_gt_channel));
array_push(_list, ["sei",        0,           _id]);
if (_sfx_is_disk) {
    array_push(_list, ["lda_imm", _sfx_blob_addr & 0xFF,        _id]);
    array_push(_list, ["ldy_imm", (_sfx_blob_addr >> 8) & 0xFF, _id]);
} else {
    array_push(_list, ["lda_lab_lo", _lbl_blob, _id]);
    array_push(_list, ["ldy_lab_hi", _lbl_blob, _id]);
}
array_push(_list, ["ldx_imm",   _gt_channel, _id]);
show_debug_message("MACRO_SFX jsr emit: sfx_entry=$" + string_upper(decimal_to_hex(_sfx_entry)) + " is_real=" + string(is_real(_sfx_entry)));
array_push(_list, ["jsr",       _sfx_entry,  _id]);
array_push(_list, ["cli",        0,           _id]);
} break;

// --------------------------------------------------------
	
// --------------------------------------------------------
// MACRO_VIC: Unified Mode Setup
// --------------------------------------------------------
case "MACRO_VIC": {
    var _id       = _curr;
    var _mode     = string(_id.instructions[0][1]);
    var _vic_bank = is_real(_id.instructions[0][2]) ? clamp(real(_id.instructions[0][2]), 0, 3) : 0;
    var _scr_addr = is_real(_id.instructions[0][3]) ? real(_id.instructions[0][3]) : 0x0400;
    var _chr_addr = is_real(_id.instructions[0][4]) ? real(_id.instructions[0][4]) : 0x2000;
    var _border   = is_real(_id.instructions[0][5]) ? real(_id.instructions[0][5]) : 0;
    var _bg0      = is_real(_id.instructions[0][6]) ? real(_id.instructions[0][6]) : 0;
    var _bg1      = is_real(_id.instructions[0][7]) ? real(_id.instructions[0][7]) : 0;
    var _bg2      = is_real(_id.instructions[0][8]) ? real(_id.instructions[0][8]) : 0;
    var _bg3      = is_real(_id.instructions[0][9]) ? real(_id.instructions[0][9]) : 0;

    var _bank_base = _vic_bank * 0x4000;
    var _cia_val   = 3 - _vic_bank;

    var _d011 = 0x1B;
    var _d016 = 0x08;
    if (_mode == "MCT")                      { _d011 = 0x1B; _d016 = 0x18; }
    if (_mode == "ECM")                      { _d011 = 0x5B; _d016 = 0x08; }
    if (_mode == "BITMAP" || _mode == "BMP") { _d011 = 0x3B; _d016 = 0x08; }
    if (_mode == "MCB")                      { _d011 = 0x3B; _d016 = 0x18; }

    // For bitmap modes, screen RAM is always chr_addr + $2000
    if (_mode == "BITMAP" || _mode == "BMP" || _mode == "MCB") {
        _scr_addr = _chr_addr + 0x2000;
    }

    var _scr_offset = floor((_scr_addr - _bank_base) / 0x0400) & 0x0F;
    var _d018_val   = 0;
    if (_mode == "BITMAP" || _mode == "BMP" || _mode == "MCB") {
        var _bmp_offset = floor((_chr_addr - _bank_base) / 0x2000) & 0x01;
        _d018_val = (_scr_offset << 4) | (_bmp_offset << 3);
    } else {
        var _chr_offset = floor((_chr_addr - _bank_base) / 0x0800) & 0x07;
        _d018_val = (_scr_offset << 4) | (_chr_offset << 1);
    }

    array_push(_list, ["sei", 0, _id]);
    // Set VIC bank via CIA2
    array_push(_list, ["lda_abs", 0xDD00,    _id]);
    array_push(_list, ["and_imm", 0xFC,       _id]);
    array_push(_list, ["ora_imm", _cia_val,   _id]);
    array_push(_list, ["sta_abs", 0xDD00,    _id]);
    // VIC registers
    array_push(_list, ["lda_imm", _d018_val, _id]);
    array_push(_list, ["sta_abs", 0xD018,    _id]);
    array_push(_list, ["lda_imm", _d011,     _id]);
    array_push(_list, ["sta_abs", 0xD011,    _id]);
    array_push(_list, ["lda_abs", 0xD016,    _id]);
array_push(_list, ["and_imm", 0x07,      _id]);
array_push(_list, ["ora_imm", _d016,     _id]);
array_push(_list, ["sta_abs", 0xD016,    _id]);
    // Border and background colours
    array_push(_list, ["lda_imm", _border,   _id]);
    array_push(_list, ["sta_abs", 0xD020,    _id]);
    array_push(_list, ["lda_imm", _bg0,      _id]);
    array_push(_list, ["sta_abs", 0xD021,    _id]);
    // Extra bg colours for multicolour/ECM modes
    if (_mode == "MCT" || _mode == "MCB") {
        array_push(_list, ["lda_imm", _bg1,  _id]);
        array_push(_list, ["sta_abs", 0xD022, _id]);
        array_push(_list, ["lda_imm", _bg2,  _id]);
        array_push(_list, ["sta_abs", 0xD023, _id]);
    }
    if (_mode == "ECM") {
        array_push(_list, ["lda_imm", _bg1,  _id]);
        array_push(_list, ["sta_abs", 0xD022, _id]);
        array_push(_list, ["lda_imm", _bg2,  _id]);
        array_push(_list, ["sta_abs", 0xD023, _id]);
        array_push(_list, ["lda_imm", _bg3,  _id]);
        array_push(_list, ["sta_abs", 0xD024, _id]);
    }
    array_push(_list, ["cli", 0, _id]);
} break;

// --------------------------------------------------------
// MACRO_SPR
// --------------------------------------------------------
case "MACRO_SPR": {
    var _id         = _curr;
    var _asset_name = string(_curr.instructions[0][1]);
    var _frame      = is_real(_curr.instructions[0][5]) ? real(_curr.instructions[0][5]) : 0;

    // Resolve all values from asset manager
    var _bank_addr  = 0x2800;
    var _screen_ram = -1;       // -1 = not set by asset, use default
    var _mc_flag    = 0;
    var _unique_col = 1;
    var _mc1        = 0;
    var _mc2        = 0;
    var _resolved   = false;

    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.name == _asset_name) {
                _bank_addr  = _a.address;
                _resolved   = true;
                // screen_ram on the asset lets users match whatever
                // MACRO_BMP or MACRO_VIC configured for $D018
                if (variable_struct_exists(_a.meta, "screen_ram"))
                    _screen_ram = _a.meta.screen_ram;
                if (variable_struct_exists(_a.meta, "sprite_mcs") && _frame < array_length(_a.meta.sprite_mcs))
                    _mc_flag = _a.meta.sprite_mcs[_frame];
                if (variable_struct_exists(_a.meta, "sprite_ucs") && _frame < array_length(_a.meta.sprite_ucs))
                    _unique_col = _a.meta.sprite_ucs[_frame];
                if (variable_struct_exists(_a.meta, "mc1_col")) _mc1 = _a.meta.mc1_col;
                if (variable_struct_exists(_a.meta, "mc2_col")) _mc2 = _a.meta.mc2_col;
                break;
            }
        }
    }

    if (!_resolved) {
        show_debug_message("MACRO_SPR WARNING: Asset '" + _asset_name + "' not found. Using fallback $6800.");
    }

    var _slot      = clamp(is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0, 0, 7);
    var _sx        = is_real(_curr.instructions[0][3]) ? real(_curr.instructions[0][3]) : 128;
    var _sy        = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) : 128;
    var _vic_bank  = _bank_addr >> 14;
    var _bank_base = _vic_bank * 0x4000;
	var _cia_val   = (3 - _vic_bank) & 0x03;

// Derive screen RAM purely from sprite load address — same logic as draw.
// Bank 0: screen at $0400. Bank 1: screen at bank_base+$2000.
// Bank 2: screen at bank_base+$3C00. Bank 3: screen at bank_base+$0400.
	if (_screen_ram == -1) {
		if (_vic_bank == 0) {
			_screen_ram = 0x0400;
		} else if (_vic_bank == 2) {
			_screen_ram = _bank_base + 0x3C00;
		} else if (_vic_bank == 3) {
			_screen_ram = _bank_base + 0x0400;
		} else {
			_screen_ram = _bank_base + 0x2000;
		}
	}

// [FIX-VIC-BANK] When MACRO_BMP is present, VIC bank is controlled by the bitmap.
	// MACRO_SPR must NOT fight over CIA $DD00. Override to match bitmap bank and screen RAM.
	// BUT: if a MACRO_VIC or MACRO_MAP is also on the main spine, the bitmap is only
	// a transient splash — the later mode switch is authoritative, so the bitmap
	// must NOT force the CIA bank back. Skip the whole override in that case.
	with (obj_c64_node) {
    if (node_type == "MACRO_BMP" && is_connected) {
			var _bmp_addr2  = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0x4000;
			var _bmp_bank2  = floor(_bmp_addr2 / 0x4000);
			var _bmp_base2  = _bmp_bank2 * 0x4000;
			var _bmp_scr2   = _bmp_addr2 + 0x2000;
			if (_bmp_bank2 == 2) _bmp_scr2 = _bmp_base2 + 0x3C00;
			if (_bmp_bank2 == 3) _bmp_scr2 = _bmp_base2 + 0x0400;
			if (_vic_bank != _bmp_bank2) {
				show_debug_message("MACRO_SPR WARNING [VIC-BANK]: Sprite '" + _asset_name
					+ "' is in VIC bank " + string(_vic_bank)
					+ " but MACRO_BMP is in bank " + string(_bmp_bank2)
					+ ". Move sprite data into bank " + string(_bmp_bank2)
					+ " (base $" + string_upper(decimal_to_hex(_bmp_base2)) + ") or sprites will not display.");
			}
			// Always defer CIA bank to the bitmap bank — bitmap wins
			_cia_val    = (3 - _bmp_bank2) & 0x03;
			_screen_ram = _bmp_scr2;
			_bank_base  = _bmp_base2;
			break;
		}
	}

	// [FIX-MAP-BANK] When MACRO_MAP is present it owns bank 0.
	// Only override if the sprite is actually in bank 0 — sprites in other
	// banks (e.g. bitmap splash sprites in bank 1) are unaffected.
	with (obj_c64_node) {
		if (node_type == "MACRO_MAP" && is_connected) {
			if (_vic_bank == 0) {
				_cia_val    = 0x03;
				_screen_ram = 0x0400;
				_bank_base  = 0x0000;
			}
			break;
		}
	}

	var _spr_ptr = ((_bank_addr - _bank_base) / 64) + _frame;
	var _ptr_reg = _screen_ram + 0x03F8 + _slot;

	// [SPR-SCROLL-FIX] If MACRO_SCROLL is on the spine it double-buffers between
	// screen 1 ($0400) and screen 2 ($0C00). Write the sprite pointer to BOTH
	// pointer tables so whichever buffer the VIC is showing has correct data.
	var _spr_has_scroll = false;
	var _ptr_reg_alt    = -1;
	with (obj_c64_node) {
		if (node_type == "MACRO_SCROLL" && is_connected) {
			_spr_has_scroll = true;
			break;
		}
	}
	if (_spr_has_scroll) {
		// MACRO_SCROLL hardcodes scr1=$0400, scr2=$0C00
		var _scr1_fixed = 0x0400;
		var _scr2_fixed = 0x0C00;
		// Pick the "other" pointer table — whichever of the two _ptr_reg isn't already
		if (_screen_ram == _scr1_fixed) {
			_ptr_reg_alt = _scr2_fixed + 0x03F8 + _slot;
		} else if (_screen_ram == _scr2_fixed) {
			_ptr_reg_alt = _scr1_fixed + 0x03F8 + _slot;
		} else {
			// Sprite asset wants a screen RAM that isn't one of the scroller's two
			// buffers — write to both anyway so the user sees something either way
			_ptr_reg     = _scr1_fixed + 0x03F8 + _slot;
			_ptr_reg_alt = _scr2_fixed + 0x03F8 + _slot;
			show_debug_message("MACRO_SPR [SPR-SCROLL-FIX]: forcing pointers to $07F8 + $0FF8 because screen_ram $"
				+ string_upper(decimal_to_hex(_screen_ram))
				+ " doesn't match scroller buffers $0400/$0C00");
		}
	}

    var _x_reg     = 0xD000 + (_slot * 2);
    var _y_reg     = 0xD001 + (_slot * 2);
    var _en_bit    = (1 << _slot);


    // 1. CIA bank select (RMW - preserves serial bus bits)
    array_push(_list, ["lda_abs", 0xDD00,   _id]);
    array_push(_list, ["and_imm", 0xFC,     _id]);
    array_push(_list, ["ora_imm", _cia_val, _id]);
    array_push(_list, ["sta_abs", 0xDD00,   _id]);

    // 2. Sprite pointer — compile-time constant
    //    Written to BOTH screen RAM pointer tables when MACRO_SCROLL is present
    array_push(_list, ["lda_imm", _spr_ptr, _id]);
    array_push(_list, ["sta_abs", _ptr_reg, _id]);
    if (_ptr_reg_alt != -1) {
        array_push(_list, ["sta_abs", _ptr_reg_alt, _id]);
    }

    // 3. Position
    array_push(_list, ["lda_imm", _sx & 0xFF, _id]);
    array_push(_list, ["sta_abs", _x_reg,     _id]);
    array_push(_list, ["lda_imm", _sy,        _id]);
    array_push(_list, ["sta_abs", _y_reg,     _id]);

    // 3b. X Coordinate MSB ($D010)
    if (_sx > 255) {
        array_push(_list, ["lda_abs", 0xD010,   _id]);
        array_push(_list, ["ora_imm", _en_bit,  _id]);
        array_push(_list, ["sta_abs", 0xD010,   _id]);
    } else {
        array_push(_list, ["lda_abs", 0xD010,                _id]);
        array_push(_list, ["and_imm", (~_en_bit) & 0xFF, _id]);
        array_push(_list, ["sta_abs", 0xD010,                _id]);
    }

    // 4. Enable sprite (OR - preserves other slots)
    array_push(_list, ["lda_abs", 0xD015,   _id]);
    array_push(_list, ["ora_imm", _en_bit,  _id]);
    array_push(_list, ["sta_abs", 0xD015,   _id]);

    // 5. Multicolour mode bit
    if (_mc_flag) {
        array_push(_list, ["lda_abs", 0xD01C,                 _id]);
        array_push(_list, ["ora_imm", (1 << _slot),           _id]);
        array_push(_list, ["sta_abs", 0xD01C,                 _id]);
    } else {
        array_push(_list, ["lda_abs", 0xD01C,                 _id]);
        array_push(_list, ["and_imm", (~(1 << _slot)) & 0xFF, _id]);
        array_push(_list, ["sta_abs", 0xD01C,                 _id]);
    }

    // 6. Sprite unique colour
    array_push(_list, ["lda_imm", _unique_col,    _id]);
    array_push(_list, ["sta_abs", 0xD027 + _slot, _id]);

    // 7. Global MC colours — always set when MC flag is on
    if (_mc_flag) {
        array_push(_list, ["lda_imm", _mc1, _id]);
        array_push(_list, ["sta_abs", 0xD025, _id]);
        array_push(_list, ["lda_imm", _mc2, _id]);
        array_push(_list, ["sta_abs", 0xD026, _id]);
    }
} break;

// --------------------------------------------------------
// MACRO_PRINT
// --------------------------------------------------------
case "MACRO_PRINT": {
    var _id          = _curr;
    var _sx          = is_real(_curr.instructions[0][1]) ? real(_curr.instructions[0][1]) : 0;
    var _sy          = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0;
    var _col         = is_real(_curr.instructions[0][3]) ? clamp(real(_curr.instructions[0][3]), 0, 15) : 1;
    var _clr         = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) : 0;
    var _align_h     = (array_length(_curr.instructions[0]) > 7) ? real(_curr.instructions[0][7]) : 0;
    var _align_v     = (array_length(_curr.instructions[0]) > 8) ? real(_curr.instructions[0][8]) : 0;

    // [9]  source mode: 0 = INLINE (existing behaviour), 1 = ASSET
    // [10] asset name (TEXT_DATA), used when [9] == 1
    // [11] start offset into asset
    // [12] end offset into asset (exclusive). 0 = "to end of asset"
    var _src_mode   = (array_length(_curr.instructions[0]) > 9  && is_real(_curr.instructions[0][9]))  ? real(_curr.instructions[0][9])  : 0;
    var _asset_name = (array_length(_curr.instructions[0]) > 10) ? string(_curr.instructions[0][10]) : "";
    var _start_off  = (array_length(_curr.instructions[0]) > 11 && is_real(_curr.instructions[0][11])) ? real(_curr.instructions[0][11]) : 0;
    var _end_off    = (array_length(_curr.instructions[0]) > 12 && is_real(_curr.instructions[0][12])) ? real(_curr.instructions[0][12]) : 0;

    // ── Resolve text + length depending on source mode ────────────
    var _text       = "";
    var _text_addr  = 0x2000;
    var _len        = 0;

    if (_src_mode == 1 && _asset_name != "") {
        // ASSET MODE — find the TEXT_DATA asset and use its address + offsets.
        // Defensively flush the asset buffer at compile time so we know it
        // contains screencodes, not raw ASCII. scr_asset_text_flush is cheap
        // and idempotent — better to spend the cycles here than to ship a
        // PRG with PETSCII glyphs on screen.
        var _asset_addr = -1;
        var _asset_sz   = 0;
        if (instance_exists(obj_asset_manager)) {
            var _am_p = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am_p.asset_list); _ai++) {
                var _a = ds_list_find_value(_am_p.asset_list, _ai);
                if (_a.type == "TEXT_DATA" && _a.name == _asset_name) {
                    scr_asset_text_flush(_a);
                    _asset_addr = _a.address;
                    if (buffer_exists(_a.buffer)) {
                        _asset_sz = buffer_get_size(_a.buffer);
                        // Strip trailing null if present (scr_asset_text_flush appends one)
                        if (_asset_sz > 0 && buffer_peek(_a.buffer, _asset_sz - 1, buffer_u8) == 0) {
                            _asset_sz--;
                        }
                    }
                    break;
                }
            }
        }
        if (_asset_addr < 0) {
            show_debug_message("MACRO_PRINT WARNING: asset '" + _asset_name + "' not found, skipping emit");
            break;
        }
        // Clamp offsets to asset size
        _start_off = clamp(_start_off, 0, _asset_sz);
        if (_end_off == 0 || _end_off > _asset_sz) _end_off = _asset_sz;
        if (_end_off < _start_off) _end_off = _start_off;
        _len       = _end_off - _start_off;
        _text_addr = _asset_addr + _start_off;
        // For alignment maths we still need a "len" string equivalent
        _text      = string_repeat(" ", _len); // placeholder used only for align maths below
    } else {
        // INLINE MODE — original behaviour
        _text      = (array_length(_id.instructions[0]) > 5) ? string(_id.instructions[0][5]) : "";
        _text_addr = (array_length(_id.instructions[0]) > 6) ? real(_id.instructions[0][6]) : 0x2000;
        _len       = string_length(_text);
    }

    // ── Alignment maths ───────────────────────────────────────────
    if (_align_h == 1)      { _sx = 0; }
    else if (_align_h == 2) { _sx = max(0, (40 - _len) div 2); }
    else if (_align_h == 3) { _sx = max(0, 40 - _len); }
    if (_align_v == 1)      { _sy = 0; }
    else if (_align_v == 2) { _sy = 12; }
    else if (_align_v == 3) { _sy = 24; }

    var _scr_base = 0x0400;
    if (array_length(_curr.instructions[0]) > 13 && is_real(_curr.instructions[0][13])) {
        _scr_base = real(_curr.instructions[0][13]);
    }
    var _offset      = (_sy * 40) + _sx;
    var _screen_dest = _scr_base + _offset;
    var _colour_dest = 0xD800 + _offset;
    var _lbl_loop    = "print_loop_"     + string(real(_id));
    var _lbl_cls     = "print_cls_loop_" + string(real(_id));

    // REPLACE:
    // ── Optional pre-clear ────────────────────────────────────────
    // Clear $0400-$07E7 (all 1000 screen RAM bytes).
    // $07F8-$07FF is the sprite pointer table — always skip it.
    if (_clr) {
        var _cls_p0 = _scr_base & 0xFF00;
        var _cls_p1 = _cls_p0 + 0x0100;
        var _cls_p2 = _cls_p0 + 0x0200;
        var _cls_p3 = _cls_p0 + 0x0300;
        var _lbl_cls2 = _lbl_cls + "_p3";
        array_push(_list, ["lda_imm", 0x20,       _id]);
        array_push(_list, ["ldx_imm", 0x00,       _id]);
        array_push(_list, ["label",   _lbl_cls        ]);
        array_push(_list, ["sta_abx", _cls_p0,    _id]);
        array_push(_list, ["sta_abx", _cls_p1,    _id]);
        array_push(_list, ["sta_abx", _cls_p2,    _id]);
        array_push(_list, ["inx",     0,          _id]);
        array_push(_list, ["bne",     _lbl_cls,   _id]);
        array_push(_list, ["label",   _lbl_cls2       ]);
        array_push(_list, ["sta_abx", _cls_p3,    _id]);
        array_push(_list, ["inx",     0,          _id]);
        array_push(_list, ["cpx_imm", 0xE8,       _id]);
        array_push(_list, ["bne",     _lbl_cls2,  _id]);
    }

    // Set cursor colour
    array_push(_list, ["lda_imm", _col,    _id]);
    array_push(_list, ["sta_abs", 0x0286,  _id]);

    // ── Resolve runtime var addresses (asset mode only) ───────────
    var _s_vmode = (_src_mode == 1 && array_length(_curr.instructions[0]) > 14 && is_real(_curr.instructions[0][14])) ? real(_curr.instructions[0][14]) : 0;
    var _s_vname = (array_length(_curr.instructions[0]) > 15) ? string(_curr.instructions[0][15]) : "";
    var _e_vmode = (_src_mode == 1 && array_length(_curr.instructions[0]) > 16 && is_real(_curr.instructions[0][16])) ? real(_curr.instructions[0][16]) : 0;
    var _e_vname = (array_length(_curr.instructions[0]) > 17) ? string(_curr.instructions[0][17]) : "";

    var _s_vaddr = -1;
    var _e_vaddr = -1;
    if (_s_vmode == 1 && _s_vname != "") {
        if (ds_map_exists(global.named_loc_map, _s_vname)) _s_vaddr = ds_map_find_value(global.named_loc_map, _s_vname);
    }
    if (_e_vmode == 1 && _e_vname != "") {
        if (ds_map_exists(global.named_loc_map, _e_vname)) _e_vaddr = ds_map_find_value(global.named_loc_map, _e_vname);
    }
    var _use_svar = (_s_vaddr >= 0);
    var _use_evar = (_e_vaddr >= 0);

    // ── Copy loop ─────────────────────────────────────────────────
    if (_use_svar || _use_evar) {
        // Runtime-driven. Source pointer ($FB/$FC) = asset_base + start (16-bit).
        // Y indexes 0..count-1 ; count = end - start (byte span, assumed <=255).
        // count stored in ZP $02 (KERNAL scratch — no keyboard scan in this macro).
        var _lbl_pskip  = "print_skip_" + string(real(_id));

        // Recover the true asset base. The asset resolver above folded the literal
        // start into _text_addr; peel it back so the runtime start-var can be added.
        var _asset_base = _text_addr;
        if (_src_mode == 1) {
            _asset_base = _text_addr - _start_off;
        }

        // ptr_lo = <base + start_lo ; ptr_hi = >base + start_hi + carry
        array_push(_list, ["clc",     0,                         _id]);
        array_push(_list, ["lda_imm", _asset_base & 0xFF,        _id]);
        if (_use_svar) {
            array_push(_list, ["adc_abs", _s_vaddr,              _id]); // + start low
        }
        array_push(_list, ["sta_zp",  0xFB,                      _id]);
        array_push(_list, ["lda_imm", (_asset_base >> 8) & 0xFF, _id]);
        if (_use_svar) {
            array_push(_list, ["adc_abs", _s_vaddr + 1,          _id]); // + start high + carry
        } else {
            array_push(_list, ["adc_imm", 0,                     _id]); // fold any carry from lo
        }
        array_push(_list, ["sta_zp",  0xFC,                      _id]);

        // count = end - start  (low bytes; span <=255 so high bytes cancel)
        array_push(_list, ["sec",     0,                         _id]);
        if (_use_evar) {
            array_push(_list, ["lda_abs", _e_vaddr,              _id]); // end low
        } else {
            array_push(_list, ["lda_imm", _end_off & 0xFF,       _id]); // literal end low
        }
        if (_use_svar) {
            array_push(_list, ["sbc_abs", _s_vaddr,              _id]); // - start low
        } else {
            array_push(_list, ["sbc_imm", _start_off & 0xFF,     _id]); // - literal start low
        }
        array_push(_list, ["sta_zp",  0x02,                      _id]); // count -> $02

        array_push(_list, ["beq",     _lbl_pskip,                _id]); // count==0 -> skip

        array_push(_list, ["ldy_imm", 0,                         _id]);
        array_push(_list, ["label",   _lbl_loop                     ]);
        array_push(_list, ["lda_izy", 0xFB,                      _id]); // lda ($FB),Y
        array_push(_list, ["sta_aby", _screen_dest,              _id]);
        array_push(_list, ["lda_imm", _col,                      _id]);
        array_push(_list, ["sta_aby", _colour_dest,              _id]);
        array_push(_list, ["iny",     0,                         _id]);
        array_push(_list, ["cpy_zp",  0x02,                      _id]); // cpy count
        array_push(_list, ["bne",     _lbl_loop,                 _id]);
        array_push(_list, ["label",   _lbl_pskip                    ]);
    } else if (_len > 0) {
        // Original constant-length path (inline + literal-offset asset)
        array_push(_list, ["ldx_imm", 0,             _id]);
        array_push(_list, ["label",   _lbl_loop          ]);
        array_push(_list, ["lda_abx", _text_addr,    _id]);
        array_push(_list, ["sta_abx", _screen_dest,  _id]);
        array_push(_list, ["lda_imm", _col,          _id]);
        array_push(_list, ["sta_abx", _colour_dest,  _id]);
        array_push(_list, ["inx",     0,             _id]);
        array_push(_list, ["cpx_imm", _len,          _id]);
        array_push(_list, ["bne",     _lbl_loop,     _id]);
    }
} break;
	
// --------------------------------------------------------
// MACRO_PRINT_EXT
// Prints a numeric value (var or CPU register) to screen RAM
// in DEC / HEX / BIN / BCD. Width follows UV meta size (1-3 bytes).
// FLAGS register is forced to BINARY with an "N V - B D I Z C"
// legend row written directly below the bits.
// Shared conversion helpers (double-dabble DEC, HEX/BIN walkers)
// are emitted once per build via global.print_ext_helpers_emitted.
//
// ZP scratch (all clobbered, IRQ-safe only if caller has SEI):
//   $FB/$FC/$FD = value lo/mid/hi (24-bit working copy)
//   $F9/$FA     = digit count / loop scratch
//   $02..$06    = double-dabble BCD scratch + bit counter
// --------------------------------------------------------
case "MACRO_PRINT_EXT": {
    var _id       = _curr;
    var _sx       = is_real(_curr.instructions[0][1]) ? clamp(real(_curr.instructions[0][1]), 0, 39) : 0;
    var _sy       = is_real(_curr.instructions[0][2]) ? clamp(real(_curr.instructions[0][2]), 0, 24) : 0;
    var _col      = is_real(_curr.instructions[0][3]) ? clamp(real(_curr.instructions[0][3]), 0, 15) : 1;
    var _clr      = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) : 0;
    var _src_mode = (array_length(_curr.instructions[0]) > 5 && is_real(_curr.instructions[0][5])) ? real(_curr.instructions[0][5]) : 0;
    var _var_name = (array_length(_curr.instructions[0]) > 6) ? string(_curr.instructions[0][6]) : "";
    var _reg_id   = (array_length(_curr.instructions[0]) > 7 && is_real(_curr.instructions[0][7])) ? real(_curr.instructions[0][7]) : 0;
    var _fmt      = (array_length(_curr.instructions[0]) > 8 && is_real(_curr.instructions[0][8])) ? real(_curr.instructions[0][8]) : 0;
    var _align_h  = (array_length(_curr.instructions[0]) > 9 && is_real(_curr.instructions[0][9])) ? real(_curr.instructions[0][9]) : 0;
    var _align_v  = (array_length(_curr.instructions[0]) > 10 && is_real(_curr.instructions[0][10])) ? real(_curr.instructions[0][10]) : 0;
    var _pad      = (array_length(_curr.instructions[0]) > 11 && is_real(_curr.instructions[0][11])) ? real(_curr.instructions[0][11]) : 0;

    // ── Resolve value width ────────────────────────────────────────
    // Registers are always 1 byte. Vars follow UV/HW meta size.
    var _size = 1;
    var _addr = 0;
    if (_src_mode == 0) {
        if (ds_map_exists(global.named_loc_map, _var_name)) {
            _addr = ds_map_find_value(global.named_loc_map, _var_name);
        }
        if (_addr == 0) {
            var _vn_find = _var_name;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _vn_find) {
                    _addr = pc_address;
                    break;
                }
            }
        }
        var _m = scr_nloc_find_meta(_var_name);
        if (_m != undefined) {
            // Derive size from encoding so it always matches the address pass
            // (scr_c64_do_update_addresses), rather than trusting a possibly
            // stale stored size field. bcd/bcd3 -> 3, word/bcd2 -> 2, else 1.
            var _enc_pe = variable_struct_exists(_m, "encoding") ? _m.encoding : "byte";
            if (_enc_pe == "bcd" || _enc_pe == "bcd3") {
                _size = 3;
            } else if (_enc_pe == "word" || _enc_pe == "bcd2") {
                _size = 2;
            } else {
                _size = 1;
            }
        }
        if (_addr == 0) {
            show_debug_message("MACRO_PRINT_EXT WARNING: var '" + _var_name + "' not resolved.");
        }
    }

    // ── FLAGS override: always binary, single byte ─────────────────
    // The status register is only meaningful bit-by-bit, so force BIN
    // regardless of the chosen format when source is the FLAGS register.
    var _is_flags = (_src_mode == 1 && _reg_id == 4);
    if (_is_flags) {
        _fmt  = 2; // force BINARY
        _size = 1; // SR is always one byte
    }

    // ── Digit count per format/width ───────────────────────────────
    // DEC: 1B=3, 2B=5, 3B=8 digits
    // HEX/BCD: 2 chars per byte
    // BIN: 8 bits per byte
    var _digits = 3;
    if (_fmt == 0) {
        if (_size == 1) _digits = 3;
        else if (_size == 2) _digits = 5;
        else _digits = 8;
    } else if (_fmt == 1 || _fmt == 3) {
        _digits = _size * 2;
    } else {
        _digits = _size * 8;
    }

    // ── Alignment (uses digit count as the "length") ──────────────
    if (_align_h == 1)      { _sx = 0; }
    else if (_align_h == 2) { _sx = max(0, (40 - _digits) div 2); }
    else if (_align_h == 3) { _sx = max(0, 40 - _digits); }
    if (_align_v == 1)      { _sy = 0; }
    else if (_align_v == 2) { _sy = 12; }
    else if (_align_v == 3) { _sy = 24; }

    var _offset      = (_sy * 40) + _sx;
    var _screen_dest = 0x0400 + _offset;
    var _colour_dest = 0xD800 + _offset;

    var _p          = "pext_" + string(real(_id)) + "_";
    var _lbl_cls    = _p + "cls";

    // ════════════════════════════════════════════════════════════════
    // SHARED HELPERS — emitted once per build, jumped over inline
    // ════════════════════════════════════════════════════════════════
    if (!global.print_ext_helpers_emitted) {
        global.print_ext_helpers_emitted = true;

        var _h_skip = "pext_helpers_skip";
        array_push(_list, ["jmp_abs", _h_skip, _id]);

        // ── HEX NIBBLE LUT: 0-9 then A-F as screencodes ──
        // Screencodes: '0'..'9' = $30..$39, 'A'..'F' = $01..$06
        array_push(_list, ["label", "pext_hexlut"]);
        var _hexcodes = [0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x01,0x02,0x03,0x04,0x05,0x06];
        for (var _hi = 0; _hi < 16; _hi++) {
            array_push(_list, ["byte", _hexcodes[_hi], _id]);
        }

        // ════════════════════════════════════════════════════════════
        // pext_dd : double-dabble 24-bit binary -> packed BCD (8 digits)
        // Input : $FB/$FC/$FD = lo/mid/hi
        // Output: $02..$05 = BCD (4 bytes, 8 nibbles, $05 = most significant)
        //         $02 = digits 0/1 (least sig pair), $05 = digits 6/7
        // Clobbers A, X, Y. Uses $06 as bit counter.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label",   "pext_dd"]);
        // Clear BCD result $02..$05
        array_push(_list, ["lda_imm", 0x00,   _id]);
        array_push(_list, ["sta_zp",  0x02,   _id]);
        array_push(_list, ["sta_zp",  0x03,   _id]);
        array_push(_list, ["sta_zp",  0x04,   _id]);
        array_push(_list, ["sta_zp",  0x05,   _id]);
        // 24 bit iterations
        array_push(_list, ["lda_imm", 24,     _id]);
        array_push(_list, ["sta_zp",  0x06,   _id]);

        array_push(_list, ["label",   "pext_dd_loop"]);
        // --- Adjust each BCD nibble >= 5 by adding 3 (before shift) ---
        // Process 4 BCD bytes ($02..$05), each holds two nibbles.
        array_push(_list, ["ldx_imm", 0x00,   _id]); // X = byte index 0..3
        array_push(_list, ["label",   "pext_dd_adj"]);
        array_push(_list, ["lda_zpx", 0x02,   _id]); // A = bcd[X]
        // low nibble
        array_push(_list, ["tay",     0,      _id]);
        array_push(_list, ["and_imm", 0x0F,   _id]);
        array_push(_list, ["cmp_imm", 0x05,   _id]);
        array_push(_list, ["bcc",     "pext_dd_lo_ok", _id]);
        array_push(_list, ["tya",     0,      _id]);
        array_push(_list, ["clc",     0,      _id]);
        array_push(_list, ["adc_imm", 0x03,   _id]);
        array_push(_list, ["tay",     0,      _id]);
        array_push(_list, ["label",   "pext_dd_lo_ok"]);
        // high nibble
        array_push(_list, ["tya",     0,      _id]);
        array_push(_list, ["and_imm", 0xF0,   _id]);
        array_push(_list, ["cmp_imm", 0x50,   _id]);
        array_push(_list, ["bcc",     "pext_dd_hi_ok", _id]);
        array_push(_list, ["tya",     0,      _id]);
        array_push(_list, ["clc",     0,      _id]);
        array_push(_list, ["adc_imm", 0x30,   _id]);
        array_push(_list, ["tay",     0,      _id]);
        array_push(_list, ["label",   "pext_dd_hi_ok"]);
        array_push(_list, ["tya",     0,      _id]);
        array_push(_list, ["sta_zpx", 0x02,   _id]); // bcd[X] = adjusted
        array_push(_list, ["inx",     0,      _id]);
        array_push(_list, ["cpx_imm", 0x04,   _id]);
        array_push(_list, ["bne",     "pext_dd_adj", _id]);

        // --- Shift entire 56-bit chain left by 1: binary then BCD ---
        // Binary $FB/$FC/$FD then BCD $02/$03/$04/$05, carry chained.
        array_push(_list, ["asl_zp",  0xFB,   _id]);
        array_push(_list, ["rol_zp",  0xFC,   _id]);
        array_push(_list, ["rol_zp",  0xFD,   _id]);
        array_push(_list, ["rol_zp",  0x02,   _id]);
        array_push(_list, ["rol_zp",  0x03,   _id]);
        array_push(_list, ["rol_zp",  0x04,   _id]);
        array_push(_list, ["rol_zp",  0x05,   _id]);

        array_push(_list, ["dec_zp",  0x06,   _id]);
        array_push(_list, ["beq",     "pext_dd_done", _id]);
        array_push(_list, ["jmp_abs", "pext_dd_loop", _id]);
        array_push(_list, ["label",   "pext_dd_done"]);
        array_push(_list, ["rts",     0,      _id]);

        array_push(_list, ["label",   _h_skip]);
    }

    // ════════════════════════════════════════════════════════════════
    // OPTIONAL PRE-CLEAR (same as MACRO_PRINT)
    // ════════════════════════════════════════════════════════════════

    // REPLACE:
    // Clear $0400-$07E7 (all 1000 screen RAM bytes).
    // $07F8-$07FF is the sprite pointer table — always skip it.
    if (_clr) {
        var _lbl_cls2 = _lbl_cls + "_p3";
        array_push(_list, ["lda_imm", 0x20,       _id]);
        array_push(_list, ["ldx_imm", 0x00,       _id]);
        array_push(_list, ["label",   _lbl_cls         ]);
        array_push(_list, ["sta_abx", 0x0400,     _id]);
        array_push(_list, ["sta_abx", 0x0500,     _id]);
        array_push(_list, ["sta_abx", 0x0600,     _id]);
        array_push(_list, ["inx",     0,          _id]);
        array_push(_list, ["bne",     _lbl_cls,   _id]);
        array_push(_list, ["label",   _lbl_cls2        ]);
        array_push(_list, ["sta_abx", 0x0700,     _id]);
        array_push(_list, ["inx",     0,          _id]);
        array_push(_list, ["cpx_imm", 0xE8,       _id]);
        array_push(_list, ["bne",     _lbl_cls2,  _id]);
    }

    // ════════════════════════════════════════════════════════════════
    // LOAD VALUE -> $FB/$FC/$FD
    // ════════════════════════════════════════════════════════════════
    if (_src_mode == 1) {
        // REGISTER source — capture into A then store
        if (_reg_id == 0) {
            // A : store as-is (user places node where A is meaningful)
            array_push(_list, ["sta_zp", 0xFB, _id]);
        } else if (_reg_id == 1) {
            array_push(_list, ["stx_zp", 0xFB, _id]); // X
        } else if (_reg_id == 2) {
            array_push(_list, ["sty_zp", 0xFB, _id]); // Y
        } else if (_reg_id == 3) {
            array_push(_list, ["tsx",    0,    _id]); // SP -> X
            array_push(_list, ["stx_zp", 0xFB, _id]);
        } else {
            array_push(_list, ["php",    0,    _id]); // FLAGS -> stack
            array_push(_list, ["pla",    0,    _id]);
            array_push(_list, ["sta_zp", 0xFB, _id]);
        }
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["sta_zp",  0xFD, _id]);
    } else {
        // VAR source
        array_push(_list, ["lda_abs", _addr, _id]);
        array_push(_list, ["sta_zp",  0xFB,  _id]);
        if (_size >= 2) {
            array_push(_list, ["lda_abs", _addr + 1, _id]);
            array_push(_list, ["sta_zp",  0xFC,      _id]);
        } else {
            array_push(_list, ["lda_imm", 0x00, _id]);
            array_push(_list, ["sta_zp",  0xFC, _id]);
        }
        if (_size >= 3) {
            array_push(_list, ["lda_abs", _addr + 2, _id]);
            array_push(_list, ["sta_zp",  0xFD,      _id]);
        } else {
            array_push(_list, ["lda_imm", 0x00, _id]);
            array_push(_list, ["sta_zp",  0xFD, _id]);
        }
    }

    // Set cursor colour (legacy, harmless)
    array_push(_list, ["lda_imm", _col,   _id]);
    array_push(_list, ["sta_abs", 0x0286, _id]);

    // ════════════════════════════════════════════════════════════════
    // FORMAT DISPATCH
    // ════════════════════════════════════════════════════════════════
    if (_fmt == 0) {
        // ─────────────── DECIMAL (via double-dabble) ───────────────
        array_push(_list, ["jsr", "pext_dd", _id]);
        // BCD result in $02..$05, 8 nibbles. Emit the rightmost _digits nibbles.
        // Nibble index 0 = low nibble of $02 (least significant digit).
        // We write MSB-first to the screen so iterate from (_digits-1) down to 0.
        var _pad_screencode = (_pad == 1) ? 0x20 : 0x30; // space or '0'
        // Leading suppression flag in $F9: 0 = still leading, 1 = real digit seen
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF9, _id]);
        for (var _di = _digits - 1; _di >= 0; _di--) {
            var _bcd_byte = 0x02 + (_di div 2);
            var _is_hi    = (_di mod 2) == 1;
            var _scr_pos  = _screen_dest + ((_digits - 1) - _di);
            var _col_pos  = _colour_dest + ((_digits - 1) - _di);
            // Load nibble into A
            array_push(_list, ["lda_zp",  _bcd_byte, _id]);
            if (_is_hi) {
                array_push(_list, ["lsr_a", 0, _id]);
                array_push(_list, ["lsr_a", 0, _id]);
                array_push(_list, ["lsr_a", 0, _id]);
                array_push(_list, ["lsr_a", 0, _id]);
            } else {
                array_push(_list, ["and_imm", 0x0F, _id]);
            }
            if (_di == 0) {
                // Last digit: always print as '0'..'9' regardless of leading state
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["adc_imm", 0x30, _id]);
                array_push(_list, ["sta_abs", _scr_pos, _id]);
            } else {
                // Leading-suppress: if A==0 AND no real digit yet, print pad char
                var _real = _p + "dr" + string(_di);
                var _wend = _p + "de" + string(_di);
                array_push(_list, ["cmp_imm", 0x00, _id]);
                array_push(_list, ["bne",     _real, _id]);
                // A == 0 : check if we've already seen a real digit
                array_push(_list, ["ldx_zp",  0xF9, _id]);
                array_push(_list, ["bne",     _real, _id]); // already printing digits
                // still leading -> pad
                array_push(_list, ["lda_imm", _pad_screencode, _id]);
                array_push(_list, ["sta_abs", _scr_pos, _id]);
                array_push(_list, ["jmp_abs", _wend, _id]);
                // real digit
                array_push(_list, ["label",   _real]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["adc_imm", 0x30, _id]);
                array_push(_list, ["sta_abs", _scr_pos, _id]);
                array_push(_list, ["lda_imm", 0x01, _id]); // mark real digit seen
                array_push(_list, ["sta_zp",  0xF9, _id]);
                array_push(_list, ["label",   _wend]);
            }
            // Colour
            array_push(_list, ["lda_imm", _col,    _id]);
            array_push(_list, ["sta_abs", _col_pos, _id]);
        }

    } else if (_fmt == 1) {
        // ─────────────── HEX ───────────────
        // Walk bytes MSB-first; per byte emit hi then lo nibble via LUT.
        // Byte order: $FD (hi) ... $FB (lo), only _size bytes used.
        var _bytes_hi_first = [];
        if (_size >= 3) array_push(_bytes_hi_first, 0xFD);
        if (_size >= 2) array_push(_bytes_hi_first, 0xFC);
        array_push(_bytes_hi_first, 0xFB);
        var _char_i = 0;
        for (var _bi = 0; _bi < array_length(_bytes_hi_first); _bi++) {
            var _zp = _bytes_hi_first[_bi];
            // high nibble
            array_push(_list, ["lda_zp",  _zp,   _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["tax",     0,     _id]);
            array_push(_list, ["lda_abx", "pext_hexlut", _id]);
            array_push(_list, ["sta_abs", _screen_dest + _char_i, _id]);
            array_push(_list, ["lda_imm", _col,  _id]);
            array_push(_list, ["sta_abs", _colour_dest + _char_i, _id]);
            _char_i++;
            // low nibble
            array_push(_list, ["lda_zp",  _zp,   _id]);
            array_push(_list, ["and_imm", 0x0F,  _id]);
            array_push(_list, ["tax",     0,     _id]);
            array_push(_list, ["lda_abx", "pext_hexlut", _id]);
            array_push(_list, ["sta_abs", _screen_dest + _char_i, _id]);
            array_push(_list, ["lda_imm", _col,  _id]);
            array_push(_list, ["sta_abs", _colour_dest + _char_i, _id]);
            _char_i++;
        }

    } else if (_fmt == 2) {
        // ─────────────── BINARY ───────────────
        // MSB-first across bytes. Shift each byte left, carry -> '0'/'1'.
        var _bytes_hi_first2 = [];
        if (_size >= 3) array_push(_bytes_hi_first2, 0xFD);
        if (_size >= 2) array_push(_bytes_hi_first2, 0xFC);
        array_push(_bytes_hi_first2, 0xFB);
        var _bit_i = 0;
        for (var _bi = 0; _bi < array_length(_bytes_hi_first2); _bi++) {
            var _zp2 = _bytes_hi_first2[_bi];
            for (var _b = 0; _b < 8; _b++) {
                var _b1 = _p + "b1_" + string(_bit_i);
                array_push(_list, ["asl_zp",  _zp2,  _id]); // MSB -> carry
                array_push(_list, ["lda_imm", 0x30,  _id]); // '0'
                array_push(_list, ["bcc",     _b1,   _id]);
                array_push(_list, ["lda_imm", 0x31,  _id]); // '1'
                array_push(_list, ["label",   _b1]);
                array_push(_list, ["sta_abs", _screen_dest + _bit_i, _id]);
                array_push(_list, ["lda_imm", _col,  _id]);
                array_push(_list, ["sta_abs", _colour_dest + _bit_i, _id]);
                _bit_i++;
            }
        }

        // ── FLAGS legend row: write "N V - B D I Z C" under the bits ──
        // Screencodes: N=$0E V=$16 -=$2D B=$02 D=$04 I=$09 Z=$1A C=$03
        // Layout mirrors SR bit order 7..0 (N V - B D I Z C).
        if (_is_flags) {
            var _legend_dest = _screen_dest + 40; // one screen row below
            var _legend_col  = _colour_dest + 40;
            var _legend = [0x0E, 0x16, 0x2D, 0x02, 0x04, 0x09, 0x1A, 0x03];
            for (var _li2 = 0; _li2 < 8; _li2++) {
                array_push(_list, ["lda_imm", _legend[_li2],          _id]);
                array_push(_list, ["sta_abs", _legend_dest + _li2,    _id]);
                array_push(_list, ["lda_imm", _col,                   _id]);
                array_push(_list, ["sta_abs", _legend_col + _li2,     _id]);
            }
        }

    } else {
        // ─────────────── BCD (already packed) ───────────────
        // Just unpack nibbles to screencodes, no conversion.
        var _bytes_hi_first3 = [];
        if (_size >= 3) array_push(_bytes_hi_first3, 0xFD);
        if (_size >= 2) array_push(_bytes_hi_first3, 0xFC);
        array_push(_bytes_hi_first3, 0xFB);
        var _char_i3 = 0;
        for (var _bi = 0; _bi < array_length(_bytes_hi_first3); _bi++) {
            var _zp3 = _bytes_hi_first3[_bi];
            // high nibble
            array_push(_list, ["lda_zp",  _zp3,  _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["lsr_a",   0,     _id]);
            array_push(_list, ["clc",     0,     _id]);
            array_push(_list, ["adc_imm", 0x30,  _id]);
            array_push(_list, ["sta_abs", _screen_dest + _char_i3, _id]);
            array_push(_list, ["lda_imm", _col,  _id]);
            array_push(_list, ["sta_abs", _colour_dest + _char_i3, _id]);
            _char_i3++;
            // low nibble
            array_push(_list, ["lda_zp",  _zp3,  _id]);
            array_push(_list, ["and_imm", 0x0F,  _id]);
            array_push(_list, ["clc",     0,     _id]);
            array_push(_list, ["adc_imm", 0x30,  _id]);
            array_push(_list, ["sta_abs", _screen_dest + _char_i3, _id]);
            array_push(_list, ["lda_imm", _col,  _id]);
            array_push(_list, ["sta_abs", _colour_dest + _char_i3, _id]);
            _char_i3++;
        }
    }
} break;

// --------------------------------------------------------
// MACRO_BMP: Koala / Raw Bitmap Auto-Config
// --------------------------------------------------------
case "MACRO_BMP": {
	var _id        = _curr;
	var _bmp_addr  = 0x4000;
	if (is_real(_id.instructions[0][2])) {
	    _bmp_addr = real(_id.instructions[0][2]);
	}

	// Asset is the source of truth for the address — the slot can be stale
	// (draw writes it, compile must not depend on draw having run). Also
	// resolve whether this asset is HiRes here, since HiRes has no colour
	// RAM channel and the copy-loop below must be skipped entirely for it.
	var _bmp_asset_name = string(_id.instructions[0][1]);
	var _bmp_is_hires   = false;
	if (instance_exists(obj_asset_manager) && _bmp_asset_name != "") {
	    var _bam = obj_asset_manager;
	    for (var _bi = 0; _bi < ds_list_size(_bam.asset_list); _bi++) {
	        var _ba = ds_list_find_value(_bam.asset_list, _bi);
	        if (_ba.type == "BITMAP" && _ba.name == _bmp_asset_name) {
	            _bmp_addr    = real(_ba.address);
	            _bmp_is_hires = scr_asset_bmp_is_hires(_ba);
	            _id.instructions[0][2] = _bmp_addr;
	            break;
	        }
	    }
	}

	// Region layout owned by scr_bmp_regions — see that script.
	var _bmp_r     = scr_bmp_regions(_bmp_addr);
	var _vic_bank  = _bmp_r.bank;
	var _bank_base = _bmp_r.bank_base;

	/*
	// Resolve Screen RAM (Source for Bitmap Colors)
	var _scr_addr = _bmp_addr + 0x2000;
	if (_vic_bank == 2) _scr_addr = _bank_base + 0x0C00;
	if (_vic_bank == 3) _scr_addr = _bank_base + 0x0400;
	*/
	var _scr_addr = _bmp_r.scr_addr;

	// VIC Register Values
	var _cia_val    = 3 - _vic_bank;
	var _bmp_offset = floor((_bmp_addr - _bank_base) / 0x2000) & 0x01;
	var _scr_offset = floor((_scr_addr - _bank_base) / 0x0400) & 0x0F;
	var _d018_val   = (_scr_offset << 4) | (_bmp_offset << 3);
	//show_debug_message("MACRO_BMP: _bmp_addr=$" + string_upper(decimal_to_hex(_bmp_addr)) + " _vic_bank=" + string(_vic_bank) + " _cia_val=" + string(_cia_val) + " _d018=$" + string_upper(decimal_to_hex(_d018_val)));

	// KLA colour source — must match the asset injector byte for byte.
	// Only meaningful for MC; HiRes has no colour-RAM channel to copy.
	var _src_col     = _bmp_r.col_addr;
	

	
	var _lbl_col_out = "col_pg_" + string(real(_id));
	var _lbl_col_rem = "col_rm_" + string(real(_id));

	// Resolve BG color from Asset Manager.
	// MC: this is the true global background (last byte of the 10003-byte
	// file). HiRes has no such byte and no global background concept — the
	// file is 9002 bytes with per-cell FG/BG in screen RAM instead — so this
	// stays 0 and is otherwise unused for HiRes below.
	var _bg_col = 0;
	if (!_bmp_is_hires && instance_exists(obj_asset_manager)) {
		var _asset_name = string(_id.instructions[0][1]);
		var _am = obj_asset_manager;
		for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
			var _a = ds_list_find_value(_am.asset_list, _ai);
			if (_a.type == "BITMAP" && _a.name == _asset_name) {
				if (buffer_exists(_a.buffer) && buffer_get_size(_a.buffer) >= 10003)
				    _bg_col = buffer_peek(_a.buffer, 10002, buffer_u8) & 0x0F;
				break;
			}
		}
	}

	array_push(_list, ["sei", 0, _id]);

	// 1. BANKING: Switch to RAM + I/O ($35) 
	// This allows us to read RAM under ROM ($E000-$FFFF) and write to Color RAM ($D800)
	array_push(_list, ["lda_imm", 0x35, _id]);
	array_push(_list, ["sta_zp",  0x01, _id]);

	// 1b. PRE-CLEAR bitmap + screen RAM to 0 (slot 4 flag).
	// Clears from the bitmap base up through the end of screen RAM using a
	// ZP pointer walk over whole pages. Adapts to the bitmap's bank/address.
	var _bmp_preclear = 0;
	if (array_length(_id.instructions[0]) > 4 && is_real(_id.instructions[0][4])) {
	    _bmp_preclear = real(_id.instructions[0][4]);
	}
	if (_bmp_preclear == 1) {
	    var _clr_lbl_pg   = "bmp_clrpg_" + string(real(_id));
	    var _clr_lbl_by   = "bmp_clrby_" + string(real(_id));
	    var _clr_start_pg = (_bmp_addr >> 8) & 0xFF;
	    var _clr_end_pg   = ((_scr_addr + 1000) >> 8) & 0xFF;
	    array_push(_list, ["lda_imm", _clr_start_pg, _id]);
	    array_push(_list, ["sta_zp",  0xFC,          _id]);
	    array_push(_list, ["lda_imm", 0x00,          _id]);
	    array_push(_list, ["sta_zp",  0xFB,          _id]);
	    array_push(_list, ["label",   _clr_lbl_pg        ]);
	    array_push(_list, ["lda_imm", 0x00,          _id]);
	    array_push(_list, ["ldy_imm", 0x00,          _id]);
	    array_push(_list, ["label",   _clr_lbl_by        ]);
	    array_push(_list, ["sta_izy", 0xFB,          _id]);
	    array_push(_list, ["iny",     0,             _id]);
	    array_push(_list, ["bne",     _clr_lbl_by,   _id]);
	    array_push(_list, ["inc_zp",  0xFC,          _id]);
	    array_push(_list, ["lda_zp",  0xFC,          _id]);
	    array_push(_list, ["cmp_imm", _clr_end_pg,   _id]);
	    array_push(_list, ["bne",     _clr_lbl_pg,   _id]);
	}

	// 2-4. COLOUR RAM COPY — MC only. HiRes bitmap mode has no colour-RAM
	// channel at all; the VIC only reads screen RAM (per-cell FG/BG nibbles)
	// and the bitmap itself, so there is nothing to copy to $D800.
	if (!_bmp_is_hires) {
		// 2. POINTER SETUP (Color Copy)
		array_push(_list, ["lda_imm", _src_col & 0xFF,        _id]);
		array_push(_list, ["sta_zp",  0xFA,                   _id]); // Source Lo
		array_push(_list, ["lda_imm", (_src_col >> 8) & 0xFF, _id]);
		array_push(_list, ["sta_zp",  0xFB,                   _id]); // Source Hi
		array_push(_list, ["lda_imm", 0x00,                   _id]);
		array_push(_list, ["sta_zp",  0xFC,                   _id]); // Dest Lo ($00)
		array_push(_list, ["lda_imm", 0xD8,                   _id]);
		array_push(_list, ["sta_zp",  0xFD,                   _id]); // Dest Hi ($D8)

		// 3. COPY LOOP (3 Full Pages)
		array_push(_list, ["ldx_imm", 0x03,        _id]);
		array_push(_list, ["ldy_imm", 0x00,        _id]);
		array_push(_list, ["label",   _lbl_col_out     ]);
		array_push(_list, ["lda_izy", 0xFA,        _id]);
		array_push(_list, ["sta_izy", 0xFC,        _id]);
		array_push(_list, ["iny",     0,           _id]);
		array_push(_list, ["bne",     _lbl_col_out, _id]);
		array_push(_list, ["inc_zp",  0xFB,        _id]);
		array_push(_list, ["inc_zp",  0xFD,        _id]);
		array_push(_list, ["dex",     0,           _id]);
		array_push(_list, ["bne",     _lbl_col_out, _id]);

		// 4. COPY REMAINDER (232 Bytes)
		array_push(_list, ["ldy_imm", 0x00,        _id]);
		array_push(_list, ["label",   _lbl_col_rem     ]);
		array_push(_list, ["lda_izy", 0xFA,        _id]);
		array_push(_list, ["sta_izy", 0xFC,        _id]);
		array_push(_list, ["iny",     0,           _id]);
		array_push(_list, ["cpy_imm", 0xE8,        _id]);
		array_push(_list, ["bne",     _lbl_col_rem, _id]);
	}

	// 5. VIC CONFIGURATION
	// Set VIC Bank ($DD00) - RMW to preserve Serial Bus
	array_push(_list, ["lda_abs", 0xDD00,   _id]);
	array_push(_list, ["and_imm", 0xFC,     _id]);
	array_push(_list, ["ora_imm", _cia_val, _id]);
	array_push(_list, ["sta_abs", 0xDD00,   _id]);

	// Set Mode and Pointers
	array_push(_list, ["lda_imm", _d018_val, _id]);
	array_push(_list, ["sta_abs", 0xD018,    _id]);
	array_push(_list, ["lda_imm", 0x3B,      _id]); // Bitmap Mode (same bit for MC and HiRes)
	array_push(_list, ["sta_abs", 0xD011,    _id]);
	array_push(_list, ["lda_imm", _bmp_is_hires ? 0x08 : 0x18, _id]); // MCM bit off for HiRes, on for MC
	array_push(_list, ["sta_abs", 0xD016,    _id]);

	// D021 has no effect on HiRes bitmap pixels (no colour RAM / global bg
	// there), but writing it is harmless, so it's left unconditional for
	// border/consistency purposes — _bg_col is simply 0 in HiRes.
	array_push(_list, ["lda_imm", _bg_col,   _id]);
	array_push(_list, ["sta_abs", 0xD021,    _id]);

/* CINEMATIC BANDING 
	// Zero screen RAM + colour RAM for top 3 and bottom 3 bitmap rows
	var _lbl_zclr_t = "bmp_zclr_t_" + string(real(_id));
	var _lbl_zclr_b = "bmp_zclr_b_" + string(real(_id));
	array_push(_list, ["lda_imm", 0x00,        _id]);
	array_push(_list, ["ldx_imm", 119,         _id]); // 3 rows * 40 - 1
	array_push(_list, ["label",   _lbl_zclr_t      ]);
	array_push(_list, ["sta_abx", _scr_addr,   _id]); // screen RAM top
	array_push(_list, ["sta_abx", 0xD800,      _id]); // colour RAM top
	array_push(_list, ["dex",     0,           _id]);
	array_push(_list, ["bpl",     _lbl_zclr_t, _id]);
	// Bottom 3 rows
	var _bot_scr = _scr_addr + (22 * 40); // row 22 onwards
	array_push(_list, ["ldx_imm", 119,         _id]);
	array_push(_list, ["label",   _lbl_zclr_b      ]);
	array_push(_list, ["sta_abx", _bot_scr,    _id]); // screen RAM bottom
	array_push(_list, ["sta_abx", 0xD800 + (22 * 40), _id]); // colour RAM bottom
	array_push(_list, ["dex",     0,           _id]);
	array_push(_list, ["bpl",     _lbl_zclr_b, _id]);
	*/

array_push(_list, ["lda_imm", 0x37, _id]);
	array_push(_list, ["sta_zp",  0x01, _id]);

	// Only emit CLI if no MACRO_IRQ nodes will handle it
	var _bmp_has_irq = false;
	with (obj_c64_node) {
		if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
			{ _bmp_has_irq = true; break; }
	}

	if (!_bmp_has_irq) array_push(_list, ["cli", 0, _id]);

} break;

// --------------------------------------------------------
// BITMAP_KLA
// --------------------------------------------------------
case "BITMAP_KLA": {
    if (variable_instance_exists(_curr, "kla_buffer")
    &&  buffer_exists(_curr.kla_buffer)) {
        var _kla_size = buffer_get_size(_curr.kla_buffer);
        for (var _bi = 0; _bi < _kla_size; _bi++) {
            array_push(_list, ["byte", buffer_peek(_curr.kla_buffer, _bi, buffer_u8)]);
        }
    }
} break;

// --------------------------------------------------------
// DATA_TEXT
// --------------------------------------------------------
case "DATA_TEXT": {
    var _raw = string(_curr.instructions[0][1]);
    for (var _s = 1; _s <= string_length(_raw); _s++) {
        var _b = string_ord_at(_raw, _s);
        if (_b >= 65 && _b <= 90)       _b -= 64;
        else if (_b >= 97 && _b <= 122) _b -= 96;
        array_push(_list, ["byte", _b]);
    }
} break;

// --------------------------------------------------------
// COND_IF_WORD — 16-bit conditional branch
// Both the source var and the compare var are "word" encoded
// (little-endian: addr = lo, addr+1 = hi). The VAR pickers filter
// to word vars only, so no width check is needed here.
//
//   eq/ne:  test high half, then low half. No ordering needed.
//   lt/gte: SEC then SBC both halves — carry holds the unsigned
//           result. The low SBC's value is discarded; only the
//           borrow propagates. CMP can't be used on the low half
//           because it would clobber the carry the high half needs.
//   gt/lte: equality test first, then the ordered compare.
//
// Every form ends in JMP — a word compare is far too long for a
// relative branch to reach the target, so the springboard is
// unconditional (same reason COND_IF force-disables its short path).
// --------------------------------------------------------
case "COND_IF_WORD": {
    var _id          = _curr;
    var _var_name    = string(_curr.instructions[0][1]);
    var _cmp_val     = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0;
    var _target      = string(_curr.instructions[0][3]);
    var _mode        = string(_curr.instructions[0][4]);
    var _addr        = 0;

    // 1. Resolve variable address (lo byte; hi byte is _addr + 1)
    if (ds_map_exists(global.named_loc_map, _var_name)) {
        _addr = ds_map_find_value(global.named_loc_map, _var_name);
    }
    if (_addr == 0) {
        var _var_name_find = _var_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                other._addr = pc_address;
                break;
            }
        }
    }

    // 2. Resolve compare var address if one is set
    var _cmp_var_name = (array_length(_curr.instructions[0]) > 5) ? string(_curr.instructions[0][5]) : "";
    var _cmp_var_addr = 0;
    if (_cmp_var_name != "") {
        if (ds_map_exists(global.named_loc_map, _cmp_var_name)) {
            _cmp_var_addr = ds_map_find_value(global.named_loc_map, _cmp_var_name);
        }
        if (_cmp_var_addr == 0) {
            var _cmp_var_find = _cmp_var_name;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _cmp_var_find) {
                    other._cmp_var_addr = pc_address;
                    break;
                }
            }
        }
    }
    var _use_var = (_cmp_var_name != "" && _cmp_var_name != "0" && _cmp_var_addr != 0);

    var _cw_lo = _cmp_val & 0xFF;
    var _cw_hi = (_cmp_val >> 8) & 0xFF;

    var _skip_lbl = "cwif_skip_" + string(real(_id));
    var _ne_lbl   = "cwif_ne_"   + string(real(_id));
    var _eq_lbl   = "cwif_eq_"   + string(real(_id));

    if (_mode == "eq" || _mode == "ne") {

        array_push(_list, ["lda_abs", _addr + 1, _id]);
        if (_use_var) {
            array_push(_list, ["cmp_abs", _cmp_var_addr + 1, _id]);
        } else {
            array_push(_list, ["cmp_imm", _cw_hi, _id]);
        }
        if (_mode == "eq") {
            array_push(_list, ["bne", _skip_lbl, _id]);
        } else {
            array_push(_list, ["bne", _ne_lbl, _id]);
        }

        array_push(_list, ["lda_abs", _addr, _id]);
        if (_use_var) {
            array_push(_list, ["cmp_abs", _cmp_var_addr, _id]);
        } else {
            array_push(_list, ["cmp_imm", _cw_lo, _id]);
        }

        if (_mode == "eq") {
            array_push(_list, ["bne", _skip_lbl, _id]);
            array_push(_list, ["jmp_abs", _target, _id]);
        } else {
            array_push(_list, ["beq", _skip_lbl, _id]);
            array_push(_list, ["label", _ne_lbl]);
            array_push(_list, ["jmp_abs", _target, _id]);
        }
        array_push(_list, ["label", _skip_lbl]);

    } else if (_mode == "lt" || _mode == "gte") {

        array_push(_list, ["lda_abs", _addr, _id]);
        array_push(_list, ["sec",     0, _id]);
        if (_use_var) {
            array_push(_list, ["sbc_abs", _cmp_var_addr, _id]);
        } else {
            array_push(_list, ["sbc_imm", _cw_lo, _id]);
        }
        array_push(_list, ["lda_abs", _addr + 1, _id]);
        if (_use_var) {
            array_push(_list, ["sbc_abs", _cmp_var_addr + 1, _id]);
        } else {
            array_push(_list, ["sbc_imm", _cw_hi, _id]);
        }

        if (_mode == "lt") {
            array_push(_list, ["bcs", _skip_lbl, _id]);
        } else {
            array_push(_list, ["bcc", _skip_lbl, _id]);
        }
        array_push(_list, ["jmp_abs", _target, _id]);
        array_push(_list, ["label", _skip_lbl]);

    } else {
        // gt  = (var != cmp) && (var >= cmp)
        // lte = (var == cmp) || (var <  cmp)

        // --- equality test ---
        array_push(_list, ["lda_abs", _addr + 1, _id]);
        if (_use_var) {
            array_push(_list, ["cmp_abs", _cmp_var_addr + 1, _id]);
        } else {
            array_push(_list, ["cmp_imm", _cw_hi, _id]);
        }
        array_push(_list, ["bne", _ne_lbl, _id]);
        array_push(_list, ["lda_abs", _addr, _id]);
        if (_use_var) {
            array_push(_list, ["cmp_abs", _cmp_var_addr, _id]);
        } else {
            array_push(_list, ["cmp_imm", _cw_lo, _id]);
        }
        array_push(_list, ["beq", _eq_lbl, _id]);
        array_push(_list, ["label", _ne_lbl]);

        // --- not equal: ordered compare ---
        array_push(_list, ["lda_abs", _addr, _id]);
        array_push(_list, ["sec",     0, _id]);
        if (_use_var) {
            array_push(_list, ["sbc_abs", _cmp_var_addr, _id]);
        } else {
            array_push(_list, ["sbc_imm", _cw_lo, _id]);
        }
        array_push(_list, ["lda_abs", _addr + 1, _id]);
        if (_use_var) {
            array_push(_list, ["sbc_abs", _cmp_var_addr + 1, _id]);
        } else {
            array_push(_list, ["sbc_imm", _cw_hi, _id]);
        }

        if (_mode == "gt") {
            // Equal -> skip. Less -> skip. Only greater falls through to JMP.
            array_push(_list, ["bcc", _skip_lbl, _id]);
            array_push(_list, ["jmp_abs", _target, _id]);
            array_push(_list, ["label", _eq_lbl]);
        } else {
            // lte: greater -> skip. Equal or less -> JMP.
            array_push(_list, ["bcs", _skip_lbl, _id]);
            array_push(_list, ["label", _eq_lbl]);
            array_push(_list, ["jmp_abs", _target, _id]);
        }
        array_push(_list, ["label", _skip_lbl]);
    }
} break;


// --------------------------------------------------------
// COND_IF - Conditional branch (Updated for Logic & Range)
// --------------------------------------------------------
case "COND_IF": {
    var _id          = _curr;
    var _var_name    = string(_curr.instructions[0][1]);
    var _cmp_val     = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0;
    var _target      = string(_curr.instructions[0][3]);
    var _mode        = string(_curr.instructions[0][4]);
    var _addr        = 0;

    // 1. Resolve variable address
    if (ds_map_exists(global.named_loc_map, _var_name)) {
        _addr = ds_map_find_value(global.named_loc_map, _var_name);
    }
    if (_addr == 0) {
        var _var_name_find = _var_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                other._addr = pc_address;
                break;
            }
        }
    }

    // 2. Resolve target label address for range check
    var _target_addr = 0;
    if (ds_map_exists(global.named_loc_map, _target)) {
        _target_addr = ds_map_find_value(global.named_loc_map, _target);
    }
    if (_target_addr == 0) {
        var _target_find = _target;
        with (obj_c64_node) {
            if (node_type == "LABEL" && string(instructions[0][1]) == _target_find) {
                _target_addr = pc_address;
                break;
            }
        }
    }

    // 3. Compile standard setup
    var _cmp_var_name = (array_length(_curr.instructions[0]) > 5) ? string(_curr.instructions[0][5]) : "";
    var _cmp_var_addr = 0;
    if (_cmp_var_name != "") {
        if (ds_map_exists(global.named_loc_map, _cmp_var_name)) {
            _cmp_var_addr = ds_map_find_value(global.named_loc_map, _cmp_var_name);
        }
        if (_cmp_var_addr == 0) {
            var _cmp_var_find = _cmp_var_name;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _cmp_var_find) {
                    other._cmp_var_addr = pc_address;
                    break;
                }
            }
        }
    }
    array_push(_list, ["lda_abs", _addr, _id]);
    if (_cmp_var_name != "" && _cmp_var_name != "0" && _cmp_var_addr != 0) {
        array_push(_list, ["cmp_abs", _cmp_var_addr, _id]);
    } else {
        array_push(_list, ["cmp_imm", _cmp_val, _id]);
    }

    // 4. Calculate if target is within 6502 relative branch range (-128 to 127)
    // We estimate from the current PC plus the size of LDA/CMP
    var _branch_from  = _curr.pc_address + 5; 
    var _offset       = _target_addr - _branch_from;
    var _in_range     = (_offset >= -126 && _offset <= 126) && (_target_addr != 0);
    
    // We force a springboard for complex multi-check logic (GT/LTE) 
    // or if the target is too far for a BXX instruction.
    var _is_complex = (_mode == "gt" || _mode == "lte");

    if (false && _in_range && !_is_complex && !global.compile_sizing_pass) {
        // --- SHORT BRANCH (Direct) ---
        var _branch = "beq";
        switch (_mode) {
            case "eq":  _branch = "beq"; break;
            case "ne":  _branch = "bne"; break;
            case "lt":  _branch = "bcc"; break;
            case "gte": _branch = "bcs"; break;
        }
        array_push(_list, [_branch, _target, _id]);
    } 
    else {
        // --- SPRINGBOARD / COMPLEX BRANCH ---
        var _skip_lbl = "cif_skip_" + string(real(_id));

        switch (_mode) {
            case "eq":
                array_push(_list, ["bne", _skip_lbl, _id]);
                array_push(_list, ["jmp_abs", _target, _id]);
                break;
            case "ne":
                array_push(_list, ["beq", _skip_lbl, _id]);
                array_push(_list, ["jmp_abs", _target, _id]);
                break;
            case "lt":
                array_push(_list, ["bcs", _skip_lbl, _id]);
                array_push(_list, ["jmp_abs", _target, _id]);
                break;
            case "gte":
                array_push(_list, ["bcc", _skip_lbl, _id]);
                array_push(_list, ["jmp_abs", _target, _id]);
                break;
            case "gt":
                // GT logic: If Zero Set (Equal), skip. If Carry Clear (Less), skip.
                array_push(_list, ["beq", _skip_lbl, _id]);
                array_push(_list, ["bcc", _skip_lbl, _id]);
                array_push(_list, ["jmp_abs", _target, _id]);
                break;
            case "lte":
                // LTE logic: If Zero Set (Equal), branch. If Carry Clear (Less), branch.
                // If it survives both, it must be GT, so skip the JMP.
                array_push(_list, ["beq", _target, _id]);   
                array_push(_list, ["bcc", _target, _id]);
                // This next JMP is only reached if A > val
                // But we need to skip it if it's NOT a springboard. 
                // To keep logic clean, we just JMP to skip.
                array_push(_list, ["jmp_abs", _skip_lbl, _id]); 
                break;
        }
        array_push(_list, ["label", _skip_lbl]);
    }
} break;
	
// --------------------------------------------------------
// BANK_SWITCH — write CPU port $01 to reconfigure memory map
// instructions[0]: ["bank_switch", v01, keep_irq_off, write_ddr, mode_index]
// --------------------------------------------------------
case "BANK_SWITCH": {
    var _id        = _curr;
    var _v01       = real(_curr.instructions[0][1]) & 0xFF;
    var _keep_irq  = real(_curr.instructions[0][2]);
    var _write_ddr = real(_curr.instructions[0][3]);

    array_push(_list, ["sei", 0, _id]);

    if (_write_ddr == 1) {
        array_push(_list, ["lda_imm", 0x2F, _id]);
        array_push(_list, ["sta_zp",  0x00, _id]);
    }

    array_push(_list, ["lda_imm", _v01, _id]);
    array_push(_list, ["sta_zp",  0x01, _id]);

    if (_keep_irq == 0) {
        array_push(_list, ["cli", 0, _id]);
    }
} break;

// --------------------------------------------------------
// MACRO_REU
// Triggers a DMA transfer on the 17xx/1750/GeoRAM-style REU at $DF00-$DF0A.
// All six address/length/bank bytes are written first, then the command
// byte is written last to $DF01 with EXEC (bit7) set, which fires the DMA.
// FF00 disable (bit5) is always set — without it, a stray write to $FF00
// (used by some cartridges/carts detection code) can retrigger the last
// queued transfer, which is a classic REU footgun.
// --------------------------------------------------------
case "MACRO_REU": {
    var _id        = _curr;
    var _reu_op    = is_real(_curr.instructions[0][1]) ? real(_curr.instructions[0][1]) : 0;
    var _reu_c64   = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) & 0xFFFF : 0xC000;
    var _reu_addr  = is_real(_curr.instructions[0][3]) ? real(_curr.instructions[0][3]) & 0xFFFF : 0x0000;
    var _reu_bank  = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) & 0xFF   : 0;
    var _reu_len   = is_real(_curr.instructions[0][5]) ? real(_curr.instructions[0][5]) & 0xFFFF : 0x0100;
    var _reu_auto  = is_real(_curr.instructions[0][6]) ? real(_curr.instructions[0][6]) : 0;
    var _reu_fixc  = is_real(_curr.instructions[0][7]) ? real(_curr.instructions[0][7]) : 0;
    var _reu_fixr  = is_real(_curr.instructions[0][8]) ? real(_curr.instructions[0][8]) : 0;

    // Type field: 00 stash, 01 fetch, 10 swap, 11 compare
    var _reu_type = clamp(_reu_op, 0, 3);

    var _reu_cmd = 0x80;               // EXEC
    _reu_cmd    |= 0x20;                // FF00 disable (always on — see note above)
    if (_reu_auto == 1) { _reu_cmd |= 0x10; }  // autoload
    _reu_cmd    |= _reu_type;

    var _reu_ctrl = 0x00;
    if (_reu_fixc == 1) { _reu_ctrl |= 0x80; } // fix C64 address
    if (_reu_fixr == 1) { _reu_ctrl |= 0x40; } // fix REU address

    array_push(_list, ["lda_imm", _reu_c64 & 0xFF,        _id]);
    array_push(_list, ["sta_abs", 0xDF02,                 _id]);
    array_push(_list, ["lda_imm", (_reu_c64 >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDF03,                 _id]);

    array_push(_list, ["lda_imm", _reu_addr & 0xFF,        _id]);
    array_push(_list, ["sta_abs", 0xDF04,                  _id]);
    array_push(_list, ["lda_imm", (_reu_addr >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDF05,                  _id]);

    array_push(_list, ["lda_imm", _reu_bank, _id]);
    array_push(_list, ["sta_abs", 0xDF06,    _id]);

    array_push(_list, ["lda_imm", _reu_len & 0xFF,        _id]);
    array_push(_list, ["sta_abs", 0xDF07,                 _id]);
    array_push(_list, ["lda_imm", (_reu_len >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDF08,                 _id]);

    array_push(_list, ["lda_imm", _reu_ctrl, _id]);
    array_push(_list, ["sta_abs", 0xDF0A,    _id]);

    array_push(_list, ["lda_imm", _reu_cmd, _id]);
    array_push(_list, ["sta_abs", 0xDF01,   _id]);
} break;

// --------------------------------------------------------
// MACRO_FLIP_X
// Flips selected sprites horizontally using a LUT.
// Reads sprite data from asset address, writes flipped copy
// to temp_addr block, updates sprite pointer table to point there.
// Two LUTs emitted inline: hi-res and multicolour.
// Auto-detects MC mode per sprite via $D01C at runtime.
// --------------------------------------------------------


// best but rewrite clobering at both sides:

case "MACRO_FLIP_X": {
    var _id    = _curr;
    var _start = 0x2800;
    if (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) {
        _start = real(_id.instructions[0][1]);
    }
    var _count = 1;
    if (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2])) {
        _count = real(_id.instructions[0][2]);
    }

    if (_count == 0) break;

    // ── Build per-sprite MC flag table ──
    var _mc_flags = array_create(_count, 0);
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.address <= _start
            &&  _a.address + buffer_get_size(_a.buffer) > _start) {
                var _base_frame = (_start - _a.address) / 64;
                for (var _fi = 0; _fi < _count; _fi++) {
                    var _fidx = _base_frame + _fi;
                    if (variable_struct_exists(_a.meta, "sprite_mcs")
                    &&  _fidx < array_length(_a.meta.sprite_mcs)) {
                        _mc_flags[_fi] = _a.meta.sprite_mcs[_fidx];
                    }
                }
                break;
            }
        }
    }

    var _pfx          = "fx" + string(real(_id)) + "_";
    var _lbl_sub      = _pfx + "sub";
    var _lbl_skip     = _pfx + "skip";
    var _lbl_outer    = _pfx + "out";
    var _lbl_mctab    = _pfx + "mct";
    var _lbl_row_hr   = _pfx + "rhr";
    var _lbl_row_mc   = _pfx + "rmc";
    var _lbl_hr_done  = _pfx + "hrd";
    var _lbl_mc_done  = _pfx + "mcd";
    var _lbl_out_done = _pfx + "odn";
    var _lbl_do_mc    = _pfx + "dmc";
    var _lbl_hr_near  = _pfx + "hrn";

    // ZP scratch — all in safe user area:
    //   $FB/$FC = sprite data pointer (KERNAL never touches)
    //   $FD     = original byte scratch
    //   $FE     = result accumulator
    //   $02     = sprite counter (free on stock C64)

    // ── JSR sub, JMP over all data ──
    array_push(_list, ["jsr",     _lbl_sub,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);

    // ── MC flag table (1 byte per sprite) ──
    array_push(_list, ["label", _lbl_mctab]);
    for (var _fi = 0; _fi < _count; _fi++) {
        array_push(_list, ["byte", _mc_flags[_fi], _id]);
    }

    // ── Subroutine ──
    array_push(_list, ["label", _lbl_sub]);
    array_push(_list, ["sei",   0, _id]); // block IRQs — protect ZP scratch + atomic flip

    // $FB/$FC = sprite data pointer
    array_push(_list, ["lda_imm", _start & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xFB,                 _id]);
    array_push(_list, ["lda_imm", (_start >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xFC,                 _id]);

    // $02 = sprite counter
    // X   = sprite index (used to look up MC table, then pushed/restored around inner loop)
    array_push(_list, ["lda_imm", _count & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0x02,          _id]);
    array_push(_list, ["ldx_imm", 0,             _id]); // X = sprite index

    // ── Outer loop — one sprite per iteration ──
    array_push(_list, ["label",   _lbl_outer]);

    // Read MC flag for this sprite using X as sprite index
    array_push(_list, ["lda_abx", _lbl_mctab,    _id]);
    array_push(_list, ["beq",     _lbl_hr_near,  _id]); // zero = hires, short branch
    array_push(_list, ["jmp_abs", _lbl_do_mc,    _id]); // springboard to MC path
    array_push(_list, ["label",   _lbl_hr_near]);

    // ════════════════════════════════════════════════════════
    // HIRES PATH
    // Push sprite index, use X as row byte offset
    // ════════════════════════════════════════════════════════
    array_push(_list, ["txa",     0,    _id]); // A = sprite index
    array_push(_list, ["pha",     0,    _id]); // stack: [sprite_idx]
    array_push(_list, ["ldx_imm", 0,    _id]); // X = row byte offset

    array_push(_list, ["label",   _lbl_row_hr]);

    // ---- HR Byte 0: read, bit-reverse, push ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+0
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+0]
    array_push(_list, ["sta_zp",  0xFD, _id]);
    array_push(_list, ["lda_imm", 0,    _id]);
    repeat(8) {
        array_push(_list, ["lsr_zp", 0xFD, _id]);
        array_push(_list, ["rol_a",  0,    _id]);
    }
    array_push(_list, ["pha",     0,    _id]); // stack: [flipped_b0, sprite_idx]

    // ---- HR Byte 2: read, bit-reverse, push, write to position 0 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+2
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+2]
    array_push(_list, ["sta_zp",  0xFD, _id]);
    array_push(_list, ["lda_imm", 0,    _id]);
    repeat(8) {
        array_push(_list, ["lsr_zp", 0xFD, _id]);
        array_push(_list, ["rol_a",  0,    _id]);
    }
    array_push(_list, ["pha",     0,    _id]); // stack: [flipped_b2, flipped_b0, sprite_idx]
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+0
    array_push(_list, ["pla",     0,    _id]); // A = flipped b2
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+0] = flipped b2

    // ---- HR Byte 0 from stack: write to position 2 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+2
    array_push(_list, ["pla",     0,    _id]); // A = flipped b0
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+2] = flipped b0
    // stack: [sprite_idx]

    // ---- HR Byte 1: read, bit-reverse, write in place ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+1
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+1]
    array_push(_list, ["sta_zp",  0xFD, _id]);
    array_push(_list, ["lda_imm", 0,    _id]);
    repeat(8) {
        array_push(_list, ["lsr_zp", 0xFD, _id]);
        array_push(_list, ["rol_a",  0,    _id]);
    }
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+1] = flipped b1 (Y still X+1)

    // ---- HR: advance X by 3, springboard loop ----
    array_push(_list, ["txa",     0,            _id]);
    array_push(_list, ["clc",     0,            _id]);
    array_push(_list, ["adc_imm", 3,            _id]);
    array_push(_list, ["tax",     0,            _id]);
    array_push(_list, ["cpx_imm", 63,           _id]);
    array_push(_list, ["beq",     _lbl_hr_done, _id]);
    array_push(_list, ["jmp_abs", _lbl_row_hr,  _id]);
    array_push(_list, ["label",   _lbl_hr_done]);

    // Restore sprite index from stack, increment for next sprite
    array_push(_list, ["pla",     0,    _id]); // A = sprite index
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]); // sprite index++
    array_push(_list, ["tax",     0,    _id]); // X = new sprite index
    array_push(_list, ["jmp_abs", _lbl_out_done, _id]); // skip MC path

    // ════════════════════════════════════════════════════════
    // MC PATH — reverse 2-bit pair order, pairs kept intact
    // Input:  [P0a|P0b|P1a|P1b|P2a|P2b|P3a|P3b]
    // Output: [P3a|P3b|P2a|P2b|P1a|P1b|P0a|P0b]
    // Push sprite index, use X as row byte offset, $FD as scratch
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_do_mc]);

    array_push(_list, ["txa",     0,    _id]); // A = sprite index
    array_push(_list, ["pha",     0,    _id]); // stack: [sprite_idx]
    array_push(_list, ["ldx_imm", 0,    _id]); // X = row byte offset

    array_push(_list, ["label",   _lbl_row_mc]);

    // ---- MC Byte 0: swap pairs, push ----
    // Load once into $FD, build result in $FE, no reloads needed
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+0
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+0] — single load
    array_push(_list, ["sta_zp",  0xFD, _id]); // $FD = original byte, preserved
    // P0 (bits 7-6) → bits 1-0
    array_push(_list, ["and_imm", 0xC0, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]); // A = 000000P0
    array_push(_list, ["sta_zp",  0xFE, _id]); // $FE = 000000P0
    // P1 (bits 5-4) → bits 3-2
    array_push(_list, ["lda_zp",  0xFD, _id]); // reload from ZP (3 cycles vs 5 for izy)
    array_push(_list, ["and_imm", 0x30, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]); // A = 0000P100
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]); // $FE = 0000P1P0
    // P2 (bits 3-2) → bits 5-4
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x0C, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]); // A = 00P20000
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]); // $FE = 00P2P1P0
    // P3 (bits 1-0) → bits 7-6
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x03, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]); // A = P3000000
    array_push(_list, ["ora_zp",  0xFE, _id]); // A = P3P2P1P0
    array_push(_list, ["pha",     0,    _id]); // stack: [swapped_b0, sprite_idx]

    // ---- MC Byte 2: swap pairs, push, write to position 0 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+2
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+2] — single load
    array_push(_list, ["sta_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0xC0, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x30, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x0C, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x03, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]); // A = swapped b2
    array_push(_list, ["pha",     0,    _id]); // stack: [swapped_b2, swapped_b0, sprite_idx]
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+0
    array_push(_list, ["pla",     0,    _id]); // A = swapped b2
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+0] = swapped b2

    // ---- MC Byte 0 from stack: write to position 2 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+2
    array_push(_list, ["pla",     0,    _id]); // A = swapped b0
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+2] = swapped b0
    // stack: [sprite_idx]

    // ---- MC Byte 1: swap pairs, write in place ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]);
    array_push(_list, ["tay",     0,    _id]); // Y = X+1
    array_push(_list, ["lda_izy", 0xFB, _id]); // A = sprite[X+1] — single load
    array_push(_list, ["sta_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0xC0, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x30, _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["lsr_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x0C, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]);
    array_push(_list, ["sta_zp",  0xFE, _id]);
    array_push(_list, ["lda_zp",  0xFD, _id]);
    array_push(_list, ["and_imm", 0x03, _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["asl_a",   0,    _id]);
    array_push(_list, ["ora_zp",  0xFE, _id]); // A = swapped b1
    array_push(_list, ["sta_izy", 0xFB, _id]); // sprite[X+1] = swapped b1 (Y still X+1)

    // ---- MC: advance X by 3, springboard loop ----
    array_push(_list, ["txa",     0,            _id]);
    array_push(_list, ["clc",     0,            _id]);
    array_push(_list, ["adc_imm", 3,            _id]);
    array_push(_list, ["tax",     0,            _id]);
    array_push(_list, ["cpx_imm", 63,           _id]);
    array_push(_list, ["beq",     _lbl_mc_done, _id]);
    array_push(_list, ["jmp_abs", _lbl_row_mc,  _id]);
    array_push(_list, ["label",   _lbl_mc_done]);

    // Restore sprite index from stack, increment for next sprite
    array_push(_list, ["pla",     0,    _id]); // A = sprite index
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]); // sprite index++
    array_push(_list, ["tax",     0,    _id]); // X = new sprite index

    // ── Both paths land here — advance pointer, next sprite ──
    var _lbl_finish = _pfx + "fin";

    array_push(_list, ["label",   _lbl_out_done]);
    array_push(_list, ["lda_zp",  0xFB,          _id]);
    array_push(_list, ["clc",     0,             _id]);
    array_push(_list, ["adc_imm", 64,            _id]);
    array_push(_list, ["sta_zp",  0xFB,          _id]);
    array_push(_list, ["lda_zp",  0xFC,          _id]);
    array_push(_list, ["adc_imm", 0,             _id]); // carry only
    array_push(_list, ["sta_zp",  0xFC,          _id]);
    array_push(_list, ["dec_zp",  0x02,          _id]);
    array_push(_list, ["beq",     _lbl_finish,   _id]); // done — fall to CLI/RTS
    array_push(_list, ["jmp_abs", _lbl_outer,    _id]); // next sprite

    array_push(_list, ["label", _lbl_finish]);
    array_push(_list, ["cli",   0, _id]); // re-enable IRQs before return
    array_push(_list, ["rts",   0, _id]);

    array_push(_list, ["label", _lbl_skip]);
} break;

/*
// expensive,fast:
case "MACRO_FLIP_X": {
    //if (global.compile_sizing_pass) break;

    var _id    = _curr;
    var _start = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1]))
               ? real(_id.instructions[0][1]) : 0x2800;
    var _count = (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2]))
               ? real(_id.instructions[0][2]) : 1;

    if (_count == 0) break;

    // ── Build per-sprite MC flag table (1 byte per sprite, 0=hires 1=MC) ──
    var _mc_flags = array_create(_count, 0);
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.address <= _start
            &&  _a.address + buffer_get_size(_a.buffer) > _start) {
                var _base_frame = (_start - _a.address) / 64;
                for (var _fi = 0; _fi < _count; _fi++) {
                    var _fidx = _base_frame + _fi;
                    _mc_flags[_fi] = (variable_struct_exists(_a.meta, "sprite_mcs")
                                   && _fidx < array_length(_a.meta.sprite_mcs))
                                   ? _a.meta.sprite_mcs[_fidx] : 0;
                }
                break;
            }
        }
    }

    var _pfx        = "fx" + string(real(_id)) + "_";
    var _lbl_sub    = _pfx + "sub";
    var _lbl_skip   = _pfx + "skip";
    var _lbl_lut_hi = _pfx + "lhi";
    var _lbl_lut_mc = _pfx + "lmc";
    var _lbl_mctab  = _pfx + "mct";
    var _lbl_outer  = _pfx + "out";
    var _lbl_row    = _pfx + "row";
    var _lbl_usemc  = _pfx + "umc";
    var _lbl_doflip = _pfx + "dof";

    // ── 1. JSR sub, JMP over all data ──
    array_push(_list, ["jsr",     _lbl_sub,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);

    // ── 2. Hires LUT (256 bytes) ──
    array_push(_list, ["label", _lbl_lut_hi]);
    var _hires_lut = [
        0x00,0x80,0x40,0xC0,0x20,0xA0,0x60,0xE0,0x10,0x90,0x50,0xD0,0x30,0xB0,0x70,0xF0,
        0x08,0x88,0x48,0xC8,0x28,0xA8,0x68,0xE8,0x18,0x98,0x58,0xD8,0x38,0xB8,0x78,0xF8,
        0x04,0x84,0x44,0xC4,0x24,0xA4,0x64,0xE4,0x14,0x94,0x54,0xD4,0x34,0xB4,0x74,0xF4,
        0x0C,0x8C,0x4C,0xCC,0x2C,0xAC,0x6C,0xEC,0x1C,0x9C,0x5C,0xDC,0x3C,0xBC,0x7C,0xFC,
        0x02,0x82,0x42,0xC2,0x22,0xA2,0x62,0xE2,0x12,0x92,0x52,0xD2,0x32,0xB2,0x72,0xF2,
        0x0A,0x8A,0x4A,0xCA,0x2A,0xAA,0x6A,0xEA,0x1A,0x9A,0x5A,0xDA,0x3A,0xBA,0x7A,0xFA,
        0x06,0x86,0x46,0xC6,0x26,0xA6,0x66,0xE6,0x16,0x96,0x56,0xD6,0x36,0xB6,0x76,0xF6,
        0x0E,0x8E,0x4E,0xCE,0x2E,0xAE,0x6E,0xEE,0x1E,0x9E,0x5E,0xDE,0x3E,0xBE,0x7E,0xFE,
        0x01,0x81,0x41,0xC1,0x21,0xA1,0x61,0xE1,0x11,0x91,0x51,0xD1,0x31,0xB1,0x71,0xF1,
        0x09,0x89,0x49,0xC9,0x29,0xA9,0x69,0xE9,0x19,0x99,0x59,0xD9,0x39,0xB9,0x79,0xF9,
        0x05,0x85,0x45,0xC5,0x25,0xA5,0x65,0xE5,0x15,0x95,0x55,0xD5,0x35,0xB5,0x75,0xF5,
        0x0D,0x8D,0x4D,0xCD,0x2D,0xAD,0x6D,0xED,0x1D,0x9D,0x5D,0xDD,0x3D,0xBD,0x7D,0xFD,
        0x03,0x83,0x43,0xC3,0x23,0xA3,0x63,0xE3,0x13,0x93,0x53,0xD3,0x33,0xB3,0x73,0xF3,
        0x0B,0x8B,0x4B,0xCB,0x2B,0xAB,0x6B,0xEB,0x1B,0x9B,0x5B,0xDB,0x3B,0xBB,0x7B,0xFB,
        0x07,0x87,0x47,0xC7,0x27,0xA7,0x67,0xE7,0x17,0x97,0x57,0xD7,0x37,0xB7,0x77,0xF7,
        0x0F,0x8F,0x4F,0xCF,0x2F,0xAF,0x6F,0xEF,0x1F,0x9F,0x5F,0xDF,0x3F,0xBF,0x7F,0xFF
    ];
    for (var _li = 0; _li < 256; _li++) {
        array_push(_list, ["byte", _hires_lut[_li], _id]);
    }

    // ── 3. MC LUT (256 bytes) ──
    array_push(_list, ["label", _lbl_lut_mc]);
    for (var _li = 0; _li < 256; _li++) {
        var _p0 = (_li >> 0) & 3;
        var _p1 = (_li >> 2) & 3;
        var _p2 = (_li >> 4) & 3;
        var _p3 = (_li >> 6) & 3;
        array_push(_list, ["byte", ((_p0 << 6) | (_p1 << 4) | (_p2 << 2) | _p3) & 0xFF, _id]);
    }

    // ── 4. MC flag table (1 byte per sprite) ──
    array_push(_list, ["label", _lbl_mctab]);
    for (var _fi = 0; _fi < _count; _fi++) {
        array_push(_list, ["byte", _mc_flags[_fi], _id]);
    }

    // ── 5. Subroutine ──
    array_push(_list, ["label", _lbl_sub]);

    // $F2/$F3 = sprite data pointer
    array_push(_list, ["lda_imm", _start & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xF2,                 _id]);
    array_push(_list, ["lda_imm", (_start >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xF3,                 _id]);

    // $F6 = sprite counter
    array_push(_list, ["lda_imm", _count & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xF6,          _id]);

    // X = sprite index (used to look up MC table)
    array_push(_list, ["ldx_imm", 0, _id]);

    // ── Outer loop — one sprite per iteration ──
    array_push(_list, ["label",   _lbl_outer]);

    // Read MC flag for this sprite: A = mc_table[X]
    array_push(_list, ["lda_abx", _lbl_mctab, _id]);
    array_push(_list, ["beq",     _lbl_doflip, _id]); // 0 = hires

    // MC: $F4/$F5 = MC LUT
    array_push(_list, ["lda_lab_lo", _lbl_lut_mc, _id]);
    array_push(_list, ["sta_zp",     0xF4,        _id]);
    array_push(_list, ["lda_lab_hi", _lbl_lut_mc, _id]);
    array_push(_list, ["sta_zp",     0xF5,        _id]);
    array_push(_list, ["jmp_abs",    _lbl_row,    _id]);

    // Hires: $F4/$F5 = hires LUT
    array_push(_list, ["label",      _lbl_doflip]);
    array_push(_list, ["lda_lab_lo", _lbl_lut_hi, _id]);
    array_push(_list, ["sta_zp",     0xF4,        _id]);
    array_push(_list, ["lda_lab_hi", _lbl_lut_hi, _id]);
    array_push(_list, ["sta_zp",     0xF5,        _id]);

    // ── Inner flip loop ──
    // X = sprite index — push it, use X as row byte offset inside loop
    array_push(_list, ["label",   _lbl_row]);
    array_push(_list, ["txa",     0,    _id]); // A = sprite index
    array_push(_list, ["pha",     0,    _id]); // push sprite index — stack: [sprite_idx]
    array_push(_list, ["ldx_imm", 0,    _id]); // X = row byte offset

    var _lbl_row2 = _pfx + "rw2";
    array_push(_list, ["label",   _lbl_row2]);

    // ---- Byte 0: read, flip, push ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF2, _id]); // A = sprite[X]
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF4, _id]); // A = LUT[sprite[X]]
    array_push(_list, ["pha",     0,    _id]); // push flipped b0  stack: [flipped_b0, sprite_idx]

    // ---- Byte 2: read, flip, write to pos 0 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF2, _id]); // A = sprite[X+2]
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF4, _id]); // A = flipped b2
    array_push(_list, ["pha",     0,    _id]); // push flipped b2  stack: [flipped_b2, flipped_b0, sprite_idx]
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["pla",     0,    _id]); // A = flipped b2
    array_push(_list, ["sta_izy", 0xF2, _id]); // sprite[X+0] = flipped b2
    // stack: [flipped_b0, sprite_idx]

    // ---- Byte 0 from stack: write to pos 2 ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 2,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["pla",     0,    _id]); // A = flipped b0
    array_push(_list, ["sta_izy", 0xF2, _id]); // sprite[X+2] = flipped b0
    // stack: [sprite_idx]

    // ---- Byte 1: read, flip, write in place ----
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF2, _id]); // A = sprite[X+1]
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["lda_izy", 0xF4, _id]); // A = flipped b1
    array_push(_list, ["pha",     0,    _id]); // push flipped b1  stack: [flipped_b1, sprite_idx]
    array_push(_list, ["txa",     0,    _id]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]);
    array_push(_list, ["tay",     0,    _id]);
    array_push(_list, ["pla",     0,    _id]); // A = flipped b1
    array_push(_list, ["sta_izy", 0xF2, _id]); // sprite[X+1] = flipped b1
    // stack: [sprite_idx]

    // Advance X by 3, inner loop until 63
    array_push(_list, ["txa",     0,         _id]);
    array_push(_list, ["clc",     0,         _id]);
    array_push(_list, ["adc_imm", 3,         _id]);
    array_push(_list, ["tax",     0,         _id]);
    array_push(_list, ["cpx_imm", 63,        _id]);
    array_push(_list, ["bne",     _lbl_row2, _id]);

    // ── End inner loop — restore sprite index, increment, advance pointer ──
    array_push(_list, ["pla",     0,    _id]); // A = sprite index
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_imm", 1,    _id]); // sprite index++
    array_push(_list, ["tax",     0,    _id]); // X = new sprite index

    // Advance $F2/$F3 by 64
    array_push(_list, ["lda_zp",  0xF2,       _id]);
    array_push(_list, ["clc",     0,          _id]);
    array_push(_list, ["adc_imm", 64,         _id]);
    array_push(_list, ["sta_zp",  0xF2,       _id]);
    array_push(_list, ["lda_zp",  0xF3,       _id]);
    array_push(_list, ["adc_imm", 0,          _id]);
    array_push(_list, ["sta_zp",  0xF3,       _id]);

    // Dec sprite count, outer loop
    array_push(_list, ["dec_zp",  0xF6,       _id]);
    array_push(_list, ["bne",     _lbl_outer, _id]);

    array_push(_list, ["rts", 0, _id]);

    array_push(_list, ["label", _lbl_skip]);
} break;

*/

// =============================================================
// MACRO_PRIORITY - SPRITES IN FRONT OR BEHIND CHARS
// =============================================================

case "MACRO_PRIORITY": {
    var _mask = real(_curr.instructions[0][1]);
    var _mode = real(_curr.instructions[0][2]); // 0=FRONT, 1=BEHIND
    var _id   = _curr;

    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    var _active = 0;
    for (var _si = 0; _si < 8; _si++) {
        if (_mask & _bit_values[_si]) _active |= _bit_values[_si];
    }

    if (_active == 0) break;

    array_push(_list, ["lda_abs", 0xD01B, _id]);
    if (_mode == 1) {
        // BEHIND: set bits
        array_push(_list, ["ora_imm", _active, _id]);
    } else {
        // FRONT: clear bits
        array_push(_list, ["and_imm", (~_active) & 0xFF, _id]);
    }
    array_push(_list, ["sta_abs", 0xD01B, _id]);

    break;
}
	
	
// =============================================================
// MACRO_SPR_ENABLE - A NICE WAY TO TOGGLE SPRITES
// =============================================================	
	
case "MACRO_SPR_ENABLE": {
    var _mask = real(_curr.instructions[0][1]);
    var _mode = real(_curr.instructions[0][2]);
    var _id   = _curr;
    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    var _active = 0;
    for (var _si = 0; _si < 8; _si++) {
        if (_mask & _bit_values[_si]) _active |= _bit_values[_si];
    }
    if (_active == 0) break;
    array_push(_list, ["lda_abs", 0xD015, _id]);
    if (_mode == 0) {
        // ENABLE: set bits
        array_push(_list, ["ora_imm", _active, _id]);
    } else {
        // DISABLE: clear bits
        array_push(_list, ["and_imm", (~_active) & 0xFF, _id]);
    }
    array_push(_list, ["sta_abs", 0xD015, _id]);
} break;



// =====================================================================
	// MACRO_SEEK — DIRECTIONAL / AI SEEK MOVEMENT
	//   [1] mask  [2] tx  [3] ty  [4] spd  [5] near  [6] spdn  [7] widex
	//   [8] bound [9] mode [10]tx_uv [11]tx_vnm [12]ty_uv [13]ty_vnm
	//   [14]dist_uv [15]dist_vnm [16]ang_uv [17]ang_vnm [18]target_sprite
	// =====================================================================
case "MACRO_SEEK": {
    var _mask     = real(_curr.instructions[0][1]) & 0xFF;
    var _tx_lit   = real(_curr.instructions[0][2]) & 0x1FF;
    var _ty_lit   = real(_curr.instructions[0][3]) & 0xFF;
    var _spd      = max(1, real(_curr.instructions[0][4]) & 0xFF);
    var _near     = real(_curr.instructions[0][5]) & 0xFF;
    var _spdn     = max(1, real(_curr.instructions[0][6]) & 0xFF);
    var _widex    = real(_curr.instructions[0][7]);
    var _bound    = real(_curr.instructions[0][8]);
    var _mode     = real(_curr.instructions[0][9]);
    var _tx_uv    = real(_curr.instructions[0][10]);
    var _tx_vnm   = string(_curr.instructions[0][11]);
    var _ty_uv    = real(_curr.instructions[0][12]);
    var _ty_vnm   = string(_curr.instructions[0][13]);
    var _dist_uv  = real(_curr.instructions[0][14]);
    var _dist_vnm = string(_curr.instructions[0][15]);
    var _ang_uv   = real(_curr.instructions[0][16]);
    var _ang_vnm  = string(_curr.instructions[0][17]);
    var _tspr_raw = (array_length(_curr.instructions[0]) > 18) ? real(_curr.instructions[0][18]) : 0;
    var _tspr_on  = 0;
    var _tspr_idx = 0;
    if (_tspr_raw >= 1 && _tspr_raw <= 8) {
        _tspr_on  = 1;
        _tspr_idx = _tspr_raw - 1;
    }
    var _id       = _curr;

    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    if (_mask == 0) break;

    var _pfx = "sk_" + string(real(_id)) + "_";

    // ---- 4-DIR axis latch table (1 byte/sprite, $FF = unset) ----
    // Persistent RAM, jumped over at runtime. Only emitted in 4-DIR mode.
    var _lbl_latch = _pfx + "latch";
    var _lbl_lskip = _pfx + "lskip";
    if (_mode == 0) {
        array_push(_list, ["jmp_abs", _lbl_lskip, _id]);
        array_push(_list, ["label",   _lbl_latch, _id]);
        for (var _li = 0; _li < 8; _li++) {
            array_push(_list, ["byte", 0xFF, _id]);
        }
        array_push(_list, ["label",   _lbl_lskip, _id]);
    }

    // bounds (match MACRO_MOVE convention)
    var _left_stop  = 23;
    var _right_stop = 253;
    if (_widex == 1) _right_stop = 321;
    var _top_stop   = 50;
    var _bot_stop   = 222;

    // ---- resolve var addresses (same pattern as MACRO_MOVE) ----
    var _tx_addr   = 0;
    var _ty_addr   = 0;
    var _dist_addr = 0;
    var _ang_addr  = 0;

    var _tx_size = 1;
    if (_tx_uv == 1 && _tx_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _tx_vnm)) _tx_addr = ds_map_find_value(global.named_loc_map, _tx_vnm);
        if (_tx_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _tx_vnm) { _tx_addr = pc_address; break; }
            }
        }
        var _txm = scr_nloc_find_meta(_tx_vnm);
        if (_txm != undefined) {
            var _txenc = variable_struct_exists(_txm, "encoding") ? _txm.encoding : "byte";
            if (_txenc == "word" || _txenc == "bcd2") _tx_size = 2;
        }
        if (_tx_addr == 0) show_debug_message("MACRO_SEEK WARNING: TGT X var '" + _tx_vnm + "' not resolved.");
    }
    if (_ty_uv == 1 && _ty_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _ty_vnm)) _ty_addr = ds_map_find_value(global.named_loc_map, _ty_vnm);
        if (_ty_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _ty_vnm) { _ty_addr = pc_address; break; }
            }
        }
        if (_ty_addr == 0) show_debug_message("MACRO_SEEK WARNING: TGT Y var '" + _ty_vnm + "' not resolved.");
    }
    if (_dist_uv == 1 && _dist_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _dist_vnm)) _dist_addr = ds_map_find_value(global.named_loc_map, _dist_vnm);
        if (_dist_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dist_vnm) { _dist_addr = pc_address; break; }
            }
        }
        if (_dist_addr == 0) show_debug_message("MACRO_SEEK WARNING: DIST var '" + _dist_vnm + "' not resolved.");
    }
    if (_ang_uv == 1 && _ang_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _ang_vnm)) _ang_addr = ds_map_find_value(global.named_loc_map, _ang_vnm);
        if (_ang_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _ang_vnm) { _ang_addr = pc_address; break; }
            }
        }
        if (_ang_addr == 0) show_debug_message("MACRO_SEEK WARNING: ANGLE var '" + _ang_vnm + "' not resolved.");
    }

    // ---- zero-page scratch (matches MACRO_MOVE's use of $FB) ----
    var _zp_txlo = 0xFB;
    var _zp_txhi = 0xFC;
    var _zp_ty   = 0xFD;
    var _zp_sx   = 0x02;
    var _zp_sxh  = 0x03;
    var _zp_sy   = 0x04;
    var _zp_dx   = 0x05;
    var _zp_dxh  = 0x06;
    var _zp_dy   = 0x07;
    var _zp_sgnx = 0x08;
    var _zp_sgny = 0x09;
    var _zp_dist = 0x0A;
    var _zp_spd  = 0x0B;

    // ---- load target into ZP (sprite / literal / var) ----
    if (_tspr_on == 1) {
        // TARGET IS A SPRITE: read live X/Y + real 9th bit from VIC.
        var _tvx  = 0xD000 + (_tspr_idx * 2);
        var _tvy  = 0xD001 + (_tspr_idx * 2);
        var _tbit = _bit_values[_tspr_idx];
        var _lbl_th0 = _pfx + "th0";
        var _lbl_the = _pfx + "the";

        array_push(_list, ["lda_abs", _tvx,     _id]);
        array_push(_list, ["sta_zp",  _zp_txlo, _id]);
        // 9th bit -> _zp_txhi (0 or 1)
        array_push(_list, ["lda_abs", 0xD010,   _id]);
        array_push(_list, ["and_imm", _tbit,    _id]);
        array_push(_list, ["beq",     _lbl_th0, _id]);
        array_push(_list, ["lda_imm", 0x01,     _id]);
        array_push(_list, ["jmp_abs", _lbl_the, _id]);
        array_push(_list, ["label",   _lbl_th0, _id]);
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["label",   _lbl_the, _id]);
        array_push(_list, ["sta_zp",  _zp_txhi, _id]);

        array_push(_list, ["lda_abs", _tvy,     _id]);
        array_push(_list, ["sta_zp",  _zp_ty,   _id]);
    } else if (_tx_uv == 1 && _tx_addr != 0) {
        array_push(_list, ["lda_abs", _tx_addr, _id]);
        array_push(_list, ["sta_zp",  _zp_txlo, _id]);
        if (_tx_size >= 2) {
            // word var — read real high byte (supports target X 256..511)
            array_push(_list, ["lda_abs", _tx_addr + 1, _id]);
            array_push(_list, ["sta_zp",  _zp_txhi,     _id]);
        } else {
            // byte var — high byte is always 0 (target X capped at 255)
            array_push(_list, ["lda_imm", 0x00,     _id]);
            array_push(_list, ["sta_zp",  _zp_txhi, _id]);
        }
    } else {
        array_push(_list, ["lda_imm", _tx_lit & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  _zp_txlo,              _id]);
        array_push(_list, ["lda_imm", (_tx_lit >> 8) & 0x01, _id]);
        array_push(_list, ["sta_zp",  _zp_txhi,              _id]);
    }
    if (_tspr_on == 1) {
        // Y already loaded above from the target sprite.
    } else if (_ty_uv == 1 && _ty_addr != 0) {
        array_push(_list, ["lda_abs", _ty_addr, _id]);
        array_push(_list, ["sta_zp",  _zp_ty,   _id]);
    } else {
        array_push(_list, ["lda_imm", _ty_lit & 0xFF, _id]);
        array_push(_list, ["sta_zp",  _zp_ty,         _id]);
    }

    // ===================================================================
    // PER-SPRITE UNROLL
    // ===================================================================
    for (var _si = 0; _si < 8; _si++) {
        if ((_mask & _bit_values[_si]) == 0) continue;

        var _vx   = 0xD000 + (_si * 2);
        var _vy   = 0xD001 + (_si * 2);
        var _bit  = _bit_values[_si];
        var _sp   = _pfx + "s" + string(_si) + "_";

        // ---- load live sprite X (+ 9th bit) ----
        array_push(_list, ["lda_abs", _vx,     _id]);
        array_push(_list, ["sta_zp",  _zp_sx,  _id]);
        if (_widex == 1) {
            var _lbl_xh0 = _sp + "xh0";
            var _lbl_xhe = _sp + "xhe";
            array_push(_list, ["lda_abs", 0xD010,  _id]);
            array_push(_list, ["and_imm", _bit,    _id]);
            array_push(_list, ["beq",     _lbl_xh0, _id]);
            array_push(_list, ["lda_imm", 0x01,    _id]);
            array_push(_list, ["jmp_abs", _lbl_xhe, _id]);
            array_push(_list, ["label",   _lbl_xh0, _id]);
            array_push(_list, ["lda_imm", 0x00,    _id]);
            array_push(_list, ["label",   _lbl_xhe, _id]);
            array_push(_list, ["sta_zp",  _zp_sxh, _id]);
        } else {
            // _widex==0 but seeker may still cross 255 — always read 9th bit
            var _lbl_sxh0 = _sp + "sxh0";
            var _lbl_sxhe = _sp + "sxhe";
            array_push(_list, ["lda_abs", 0xD010,   _id]);
            array_push(_list, ["and_imm", _bit,     _id]);
            array_push(_list, ["beq",     _lbl_sxh0, _id]);
            array_push(_list, ["lda_imm", 0x01,     _id]);
            array_push(_list, ["jmp_abs", _lbl_sxhe, _id]);
            array_push(_list, ["label",   _lbl_sxh0, _id]);
            array_push(_list, ["lda_imm", 0x00,     _id]);
            array_push(_list, ["label",   _lbl_sxhe, _id]);
            array_push(_list, ["sta_zp",  _zp_sxh,  _id]);
        }
        array_push(_list, ["lda_abs", _vy,    _id]);
        array_push(_list, ["sta_zp",  _zp_sy, _id]);

        // ---- dx = tx - sx (16-bit) ; sgnx ; abs ----
        var _lbl_xpos = _sp + "xpos";
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["sta_zp",  _zp_sgnx, _id]);
        array_push(_list, ["sec",     0,        _id]);
        array_push(_list, ["lda_zp",  _zp_txlo, _id]);
        array_push(_list, ["sbc_zp",  _zp_sx,   _id]);
        array_push(_list, ["sta_zp",  _zp_dx,   _id]);
        array_push(_list, ["lda_zp",  _zp_txhi, _id]);
        array_push(_list, ["sbc_zp",  _zp_sxh,  _id]);
        array_push(_list, ["sta_zp",  _zp_dxh,  _id]);
        array_push(_list, ["bpl",     _lbl_xpos, _id]); // hi bit7 clear => positive
        // negative: sgnx=1, negate 16-bit (0 - dx)
        array_push(_list, ["lda_imm", 0x01,     _id]);
        array_push(_list, ["sta_zp",  _zp_sgnx, _id]);
        array_push(_list, ["sec",     0,        _id]);
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["sbc_zp",  _zp_dx,   _id]);
        array_push(_list, ["sta_zp",  _zp_dx,   _id]);
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["sbc_zp",  _zp_dxh,  _id]);
        array_push(_list, ["sta_zp",  _zp_dxh,  _id]);
        array_push(_list, ["label",   _lbl_xpos, _id]);

        // ---- dy = ty - sy (8-bit) ; sgny ; abs ----
        var _lbl_ypos = _sp + "ypos";
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["sta_zp",  _zp_sgny, _id]);
        array_push(_list, ["sec",     0,        _id]);
        array_push(_list, ["lda_zp",  _zp_ty,   _id]);
        array_push(_list, ["sbc_zp",  _zp_sy,   _id]);
        array_push(_list, ["sta_zp",  _zp_dy,   _id]);
        array_push(_list, ["bpl",     _lbl_ypos, _id]);
        array_push(_list, ["lda_imm", 0x01,     _id]);
        array_push(_list, ["sta_zp",  _zp_sgny, _id]);
        array_push(_list, ["sec",     0,        _id]);
        array_push(_list, ["lda_imm", 0x00,     _id]);
        array_push(_list, ["sbc_zp",  _zp_dy,   _id]);
        array_push(_list, ["sta_zp",  _zp_dy,   _id]);
        array_push(_list, ["label",   _lbl_ypos, _id]);

        // ---- manhattan dist = |dx| + |dy|, clamp 255 ----
        var _lbl_d255 = _sp + "d255";
        var _lbl_dend = _sp + "dend";
        array_push(_list, ["lda_zp",  _zp_dxh,  _id]);
        array_push(_list, ["bne",     _lbl_d255, _id]); // dx hi nonzero => >255
        array_push(_list, ["lda_zp",  _zp_dx,   _id]);
        array_push(_list, ["clc",     0,        _id]);
        array_push(_list, ["adc_zp",  _zp_dy,   _id]);
        array_push(_list, ["bcc",     _lbl_dend, _id]); // no carry => fits
        array_push(_list, ["label",   _lbl_d255, _id]);
        array_push(_list, ["lda_imm", 0xFF,     _id]);
        array_push(_list, ["label",   _lbl_dend, _id]);
        array_push(_list, ["sta_zp",  _zp_dist, _id]);

        // ---- choose speed ----
        array_push(_list, ["lda_imm", _spd,    _id]);
        array_push(_list, ["sta_zp",  _zp_spd, _id]);
        if (_near > 0) {
            var _lbl_keep = _sp + "keep";
            array_push(_list, ["lda_zp",  _zp_dist, _id]);
            array_push(_list, ["cmp_imm", _near,    _id]);
            array_push(_list, ["bcs",     _lbl_keep, _id]); // dist>=near => keep spd
            array_push(_list, ["lda_imm", _spdn,    _id]);
            array_push(_list, ["sta_zp",  _zp_spd,  _id]);
            array_push(_list, ["label",   _lbl_keep, _id]);
        }

        // ===============================================================
        // 4-DIR AXIS LATCH ($0D := latch[_si]): 1 = locked X, 0 = locked Y.
        // Strict L-path: stay on the locked axis until its delta hits 0,
        // then clear the latch and re-pick the dominant axis this frame.
        //   X dominant when dxh != 0, or |dx| >= |dy|. Ties go to X.
        // ===============================================================
        if (_mode == 0) {
            var _lbl_xwin = _sp + "xwin";
            var _lbl_pick = _sp + "pick";
            var _lbl_use  = _sp + "use";   // A holds latch value -> store $0D, fall through
            var _lbl_clrx = _sp + "clrx";

            // Load this sprite's latch into A (X = index, kept for any store)
            array_push(_list, ["ldx_imm", _si,         _id]);
            array_push(_list, ["lda_abx", _lbl_latch,  _id]);

            // If latch == $FF (unset) -> pick now
            array_push(_list, ["cmp_imm", 0xFF,        _id]);
            array_push(_list, ["beq",     _lbl_pick,   _id]);

            // Latched. Locked axis still open? keep (A already = latch -> _use).
            array_push(_list, ["cmp_imm", 0x01,        _id]); // A==1 -> locked X
            array_push(_list, ["beq",     _lbl_clrx,   _id]);
            // locked Y: open when |dy| != 0
            array_push(_list, ["ldy_zp",  _zp_dy,      _id]); // test dy without losing A
            array_push(_list, ["bne",     _lbl_use,    _id]); // Y open -> keep (A=0)
            array_push(_list, ["jmp_abs", _lbl_pick,   _id]); // Y closed -> re-pick
            // locked X: open when dxh!=0 OR |dx|!=0
            array_push(_list, ["label",   _lbl_clrx, _id]);
            array_push(_list, ["ldy_zp",  _zp_dxh,     _id]);
            array_push(_list, ["bne",     _lbl_use,    _id]); // X open -> keep (A=1)
            array_push(_list, ["ldy_zp",  _zp_dx,      _id]);
            array_push(_list, ["bne",     _lbl_use,    _id]); // X open -> keep (A=1)
            // fall through -> X closed -> re-pick

            // ---- PICK dominant axis (result in A), store to latch[_si] ----
            array_push(_list, ["label",   _lbl_pick, _id]);
            array_push(_list, ["lda_zp",  _zp_dxh,     _id]);
            array_push(_list, ["bne",     _lbl_xwin,   _id]); // dxh!=0 -> X wins
            array_push(_list, ["lda_zp",  _zp_dx,      _id]);
            array_push(_list, ["cmp_zp",  _zp_dy,      _id]);
            array_push(_list, ["bcs",     _lbl_xwin,   _id]); // |dx|>=|dy| -> X (tie->X)
            array_push(_list, ["lda_imm", 0x00,        _id]); // Y wins
            array_push(_list, ["bcc",     _lbl_use + "_store", _id]); // always taken (carry clear from cmp)
            array_push(_list, ["label",   _lbl_xwin, _id]);
            array_push(_list, ["lda_imm", 0x01,        _id]); // X wins
            array_push(_list, ["label",   _lbl_use + "_store", _id]);
            array_push(_list, ["ldx_imm", _si,         _id]); // cmp path may have left X intact, but be safe
            array_push(_list, ["sta_abx", _lbl_latch,  _id]); // persist freshly-picked latch

            // ---- A holds latch value (kept or freshly picked) -> $0D ----
            array_push(_list, ["label",   _lbl_use, _id]);
            array_push(_list, ["sta_zp",  0x0D,        _id]);
        }

        // ===============================================================
        // X-AXIS STEP
        //   step = min(spd, |dx|)  (no overshoot)
        //   4-DIR: only if X is the dominant axis (flag $0D == 1)
        //   8-DIR / VECTOR: always when |dx|>0
        // ===============================================================
        var _lbl_xskip = _sp + "xskip";

        // 4-DIR gate: skip X entirely unless X is dominant.
        // beq target may be >127 bytes away, so branch over a long jmp instead.
        if (_mode == 0) {
            var _lbl_xgate = _sp + "xgate";
            array_push(_list, ["lda_zp",  0x0D,      _id]);
            array_push(_list, ["bne",     _lbl_xgate, _id]); // X dominant -> run X block
            array_push(_list, ["jmp_abs", _lbl_xskip, _id]); // Y dominant -> skip X (long jump)
            array_push(_list, ["label",   _lbl_xgate, _id]);
        }

        // if |dx|==0 (and dxh==0) skip
        var _lbl_xgo = _sp + "xgo";
        array_push(_list, ["lda_zp",  _zp_dxh,  _id]);
        array_push(_list, ["bne",     _lbl_xgo, _id]);
        array_push(_list, ["lda_zp",  _zp_dx,   _id]);
        array_push(_list, ["bne",     _lbl_xgo, _id]);
        array_push(_list, ["jmp_abs", _lbl_xskip, _id]);
        array_push(_list, ["label",   _lbl_xgo, _id]);

        // step = min(spd, |dx|): if dxh==0 and dx<spd then step=dx else step=spd
        // (A = step) -> store in zp_spd-shadow via X reg
        var _lbl_xclamp = _sp + "xclamp";
        var _lbl_xstep  = _sp + "xstep";
        array_push(_list, ["lda_zp",  _zp_dxh,  _id]);
        array_push(_list, ["bne",     _lbl_xstep, _id]); // dx>=256 => use full spd
        array_push(_list, ["lda_zp",  _zp_dx,   _id]);
        array_push(_list, ["cmp_zp",  _zp_spd,  _id]);
        array_push(_list, ["bcs",     _lbl_xstep, _id]); // |dx|>=spd => use spd
        // |dx| < spd => step = |dx|
        array_push(_list, ["lda_zp",  _zp_dx,   _id]);
        array_push(_list, ["jmp_abs", _lbl_xclamp, _id]);
        array_push(_list, ["label",   _lbl_xstep, _id]);
        array_push(_list, ["lda_zp",  _zp_spd,  _id]);
        array_push(_list, ["label",   _lbl_xclamp, _id]);
        array_push(_list, ["tax",     0,        _id]); // X = step magnitude

        // apply to sprite: sgnx==0 => add, else subtract. BOUNDED clamps at walls.
        var _lbl_xneg  = _sp + "xn";
        var _lbl_xdone = _sp + "xd";
        array_push(_list, ["lda_zp",  _zp_sgnx, _id]);
        array_push(_list, ["bne",     _lbl_xneg, _id]);

        // ----- X positive (move right) -----
        // Add step. A = new X lo, carry = crossed 255 upward this frame.
        array_push(_list, ["txa",     0,    _id]);  // A = step
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_abs", _vx,  _id]);  // A = new X lo, C set if crossed 255
        if (_bound == 1) {
            // BOUNDED: keep seeker inside the playfield, never the border.
            // Current 9th bit is in _zp_sxh (read at top of this sprite).
            if (_widex) {
                // Playfield can extend past 255. Build 9-bit new pos:
                //   new_hi = sxh + carry
                // Then clamp the 9-bit value to right_stop (which may be > 255).
                var _lbl_xp_hi   = _sp + "xphi";
                var _lbl_xp_clmp = _sp + "xpcl";
                var _lbl_xp_set  = _sp + "xpst";
                var _lbl_xp_clr  = _sp + "xpclr";
                var _lbl_xp_ok   = _sp + "xpok";

                array_push(_list, ["sta_zp",  0x0C,     _id]); // park new lo
                // new_hi = sxh + carry
                array_push(_list, ["lda_zp",  _zp_sxh,  _id]);
                array_push(_list, ["adc_imm", 0x00,     _id]); // +carry
                array_push(_list, ["sta_zp",  0x0E,     _id]); // park new hi (0 or 1)

                // Clamp: if new_hi > right_hi -> clamp. If new_hi == right_hi and lo >= right_lo -> clamp.
                array_push(_list, ["cmp_imm", (_right_stop >> 8) & 0x01, _id]); // A=new_hi
                array_push(_list, ["bcc",     _lbl_xp_ok,   _id]); // new_hi < right_hi -> safe
                array_push(_list, ["bne",     _lbl_xp_clmp, _id]); // new_hi > right_hi -> clamp
                // hi equal: compare lo
                array_push(_list, ["lda_zp",  0x0C,     _id]);
                array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                array_push(_list, ["bcc",     _lbl_xp_ok,   _id]); // lo < right_lo -> safe
                array_push(_list, ["label",   _lbl_xp_clmp, _id]);
                // clamp to right_stop
                array_push(_list, ["lda_imm", _right_stop & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0x0C,     _id]);
                array_push(_list, ["lda_imm", (_right_stop >> 8) & 0x01, _id]);
                array_push(_list, ["sta_zp",  0x0E,     _id]);
                array_push(_list, ["label",   _lbl_xp_ok, _id]);
                // write lo
                array_push(_list, ["lda_zp",  0x0C,     _id]);
                array_push(_list, ["sta_abs", _vx,      _id]);
                // set/clear 9th bit explicitly from new_hi
                array_push(_list, ["lda_zp",  0x0E,     _id]);
                array_push(_list, ["beq",     _lbl_xp_clr, _id]);
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["ora_imm", _bit,     _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
                array_push(_list, ["jmp_abs", _lbl_xdone, _id]);
                array_push(_list, ["label",   _lbl_xp_clr, _id]);
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["and_imm", ~_bit & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
            } else {
                // Single-byte playfield: right_stop <= 255.
                // Carry set => crossed 255 => definitely past wall => clamp.
                var _lbl_xp_clmp = _sp + "xpcl";
                var _lbl_xp_ok   = _sp + "xpok";
                array_push(_list, ["bcs",     _lbl_xp_clmp, _id]); // carry -> clamp
                array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                array_push(_list, ["bcc",     _lbl_xp_ok,   _id]); // new < right_stop -> safe
                array_push(_list, ["label",   _lbl_xp_clmp, _id]);
                array_push(_list, ["lda_imm", _right_stop & 0xFF, _id]);
                array_push(_list, ["label",   _lbl_xp_ok,   _id]);
                array_push(_list, ["sta_abs", _vx,  _id]);
                // 9th bit stays clear in single-byte playfield
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["and_imm", ~_bit & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
            }
        } else {
            // UNBOUNDED: free movement, set 9th bit on upward crossing.
            array_push(_list, ["sta_abs", _vx,  _id]);
            if (_widex) {
                var _lbl_xpnf = _sp + "xpnf";
                array_push(_list, ["bcc",     _lbl_xpnf, _id]);
                array_push(_list, ["lda_abs", 0xD010,    _id]);
                array_push(_list, ["ora_imm", _bit,      _id]);
                array_push(_list, ["sta_abs", 0xD010,    _id]);
                array_push(_list, ["label",   _lbl_xpnf, _id]);
            }
        }
        array_push(_list, ["jmp_abs", _lbl_xdone, _id]);

        // ----- X negative (move left) -----
        array_push(_list, ["label", _lbl_xneg, _id]);
        // Subtract step. A = new X lo, carry CLEAR = borrowed (crossed 256 downward).
        array_push(_list, ["lda_abs", _vx,  _id]);
        array_push(_list, ["stx_zp",  0x0C, _id]); // park step in scratch
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0x0C, _id]);  // A = new X lo
        if (_bound == 1) {
            // BOUNDED: never enter the left border. left_stop is always <= 255.
            if (_widex) {
                // 9-bit new pos. new_hi tracked explicitly in $0E (0 or 1).
                //   no borrow  -> new_hi = old hi (unchanged)
                //   borrow     -> new_hi = old hi - 1:
                //                   old hi==1 -> new_hi=0, lo valid
                //                   old hi==0 -> underflow -> clamp lo to left_stop, new_hi=0
                // Then floor: if new_hi==0 and lo < left_stop -> lo=left_stop.
                // Finally set/clear 9th bit from new_hi (never unconditional).
                var _lbl_xn_borrow = _sp + "xnbr";
                var _lbl_xn_floor  = _sp + "xnfl";
                var _lbl_xn_write  = _sp + "xnwr";
                var _lbl_xn_setbit = _sp + "xnsb";
                var _lbl_xn_clrbit = _sp + "xncb";

                array_push(_list, ["sta_zp",  0x0C,     _id]); // park tentative new lo
                array_push(_list, ["bcc",     _lbl_xn_borrow, _id]); // borrow -> hi drops

                // ---- no borrow: new_hi = old hi ----
                array_push(_list, ["lda_zp",  _zp_sxh,  _id]);
                array_push(_list, ["sta_zp",  0x0E,     _id]); // new_hi = old hi
                array_push(_list, ["jmp_abs", _lbl_xn_floor, _id]);

                // ---- borrow: new_hi = old hi - 1 ----
                array_push(_list, ["label",   _lbl_xn_borrow, _id]);
                array_push(_list, ["lda_zp",  _zp_sxh,  _id]);
                array_push(_list, ["bne",     _lbl_xn_setbit, _id]); // old hi==1 -> new_hi=0, lo valid
                // old hi==0 and borrowed -> underflow -> clamp lo, new_hi=0
                array_push(_list, ["lda_imm", _left_stop, _id]);
                array_push(_list, ["sta_zp",  0x0C,     _id]);
                array_push(_list, ["lda_imm", 0x00,     _id]);
                array_push(_list, ["sta_zp",  0x0E,     _id]);
                array_push(_list, ["jmp_abs", _lbl_xn_write, _id]);
                array_push(_list, ["label",   _lbl_xn_setbit, _id]);
                array_push(_list, ["lda_imm", 0x00,     _id]); // old hi was 1 -> new_hi 0
                array_push(_list, ["sta_zp",  0x0E,     _id]);
                array_push(_list, ["jmp_abs", _lbl_xn_write, _id]);

                // ---- floor (only when new_hi==0): lo must be >= left_stop ----
                array_push(_list, ["label",   _lbl_xn_floor, _id]);
                array_push(_list, ["lda_zp",  0x0E,     _id]);
                array_push(_list, ["bne",     _lbl_xn_write, _id]); // new_hi==1 -> any lo fine
                array_push(_list, ["lda_zp",  0x0C,     _id]);
                array_push(_list, ["cmp_imm", _left_stop, _id]);
                array_push(_list, ["bcs",     _lbl_xn_write, _id]); // lo >= left_stop -> fine
                array_push(_list, ["lda_imm", _left_stop, _id]);
                array_push(_list, ["sta_zp",  0x0C,     _id]);

                // ---- write lo, then set/clear 9th bit from new_hi ----
                array_push(_list, ["label",   _lbl_xn_write, _id]);
                array_push(_list, ["lda_zp",  0x0C,     _id]);
                array_push(_list, ["sta_abs", _vx,      _id]);
                array_push(_list, ["lda_zp",  0x0E,     _id]);
                array_push(_list, ["beq",     _lbl_xn_clrbit, _id]);
                // new_hi==1 -> SET bit
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["ora_imm", _bit,     _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
                array_push(_list, ["jmp_abs", _lbl_xdone, _id]);
                // new_hi==0 -> CLEAR bit
                array_push(_list, ["label",   _lbl_xn_clrbit, _id]);
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["and_imm", ~_bit & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
            } else {
                // Single-byte playfield.
                var _lbl_xn_clmp = _sp + "xncl";
                var _lbl_xn_ok   = _sp + "xnok";
                array_push(_list, ["bcc",     _lbl_xn_clmp, _id]); // borrow -> underflow -> clamp
                array_push(_list, ["cmp_imm", _left_stop, _id]);
                array_push(_list, ["bcs",     _lbl_xn_ok,   _id]); // new >= left_stop -> fine
                array_push(_list, ["label",   _lbl_xn_clmp, _id]);
                array_push(_list, ["lda_imm", _left_stop, _id]);
                array_push(_list, ["label",   _lbl_xn_ok,   _id]);
                array_push(_list, ["sta_abs", _vx,  _id]);
                array_push(_list, ["lda_abs", 0xD010,   _id]);
                array_push(_list, ["and_imm", ~_bit & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,   _id]);
            }
        } else {
            // UNBOUNDED.
            array_push(_list, ["sta_abs", _vx,  _id]);
            if (_widex) {
                var _lbl_xnnf = _sp + "xnnf";
                array_push(_list, ["bcs",     _lbl_xnnf, _id]);
                array_push(_list, ["lda_abs", 0xD010,    _id]);
                array_push(_list, ["and_imm", ~_bit & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,    _id]);
                array_push(_list, ["label",   _lbl_xnnf, _id]);
            }
        }
        array_push(_list, ["label", _lbl_xdone, _id]);
        array_push(_list, ["label", _lbl_xskip, _id]);

        // ===============================================================
        // Y-AXIS STEP
        // ===============================================================
        var _lbl_yskip = _sp + "yskip";

        // 4-DIR gate: skip Y entirely unless Y is dominant (flag $0D == 0).
        // bne target may be >127 bytes away, so branch over a long jmp instead.
        if (_mode == 0) {
            var _lbl_ygate = _sp + "ygate";
            array_push(_list, ["lda_zp",  0x0D,      _id]);
            array_push(_list, ["beq",     _lbl_ygate, _id]); // Y dominant -> run Y block
            array_push(_list, ["jmp_abs", _lbl_yskip, _id]); // X dominant -> skip Y (long jump)
            array_push(_list, ["label",   _lbl_ygate, _id]);
        }

        // if |dy|==0 skip
        var _lbl_ygo = _sp + "ygo";
        array_push(_list, ["lda_zp",  _zp_dy,   _id]);
        array_push(_list, ["bne",     _lbl_ygo, _id]);
        array_push(_list, ["jmp_abs", _lbl_yskip, _id]);
        array_push(_list, ["label",   _lbl_ygo, _id]);

        // step = min(spd, |dy|)
        var _lbl_yclamp = _sp + "yclamp";
        var _lbl_ystep  = _sp + "ystep";
        array_push(_list, ["lda_zp",  _zp_dy,   _id]);
        array_push(_list, ["cmp_zp",  _zp_spd,  _id]);
        array_push(_list, ["bcs",     _lbl_ystep, _id]);
        array_push(_list, ["lda_zp",  _zp_dy,   _id]);
        array_push(_list, ["jmp_abs", _lbl_yclamp, _id]);
        array_push(_list, ["label",   _lbl_ystep, _id]);
        array_push(_list, ["lda_zp",  _zp_spd,  _id]);
        array_push(_list, ["label",   _lbl_yclamp, _id]);
        array_push(_list, ["tax",     0,        _id]); // X = step

        var _lbl_yneg  = _sp + "yn";
        var _lbl_ydone = _sp + "yd";
        array_push(_list, ["lda_zp",  _zp_sgny, _id]);
        array_push(_list, ["bne",     _lbl_yneg, _id]);

        // ----- Y positive (down) -----
        array_push(_list, ["txa",     0,   _id]);
        array_push(_list, ["clc",     0,   _id]);
        array_push(_list, ["adc_abs", _vy, _id]);  // A = new Y
        if (_bound == 1) {
            var _lbl_yp_ok = _sp + "ypok";
            array_push(_list, ["cmp_imm", _bot_stop, _id]);
            array_push(_list, ["bcc",     _lbl_yp_ok, _id]); // new Y < bot_stop -> fine
            array_push(_list, ["lda_imm", _bot_stop,  _id]); // clamp to bot_stop
            array_push(_list, ["label",   _lbl_yp_ok, _id]);
        }
        array_push(_list, ["sta_abs", _vy, _id]);
        array_push(_list, ["jmp_abs", _lbl_ydone, _id]);

        // ----- Y negative (up) -----
        array_push(_list, ["label", _lbl_yneg, _id]);
        array_push(_list, ["lda_abs", _vy,  _id]);
        array_push(_list, ["stx_zp",  0x0C, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0x0C, _id]);  // A = new Y
        if (_bound == 1) {
            var _lbl_yn_ok = _sp + "ynok";
            array_push(_list, ["bcs",     _lbl_yn_ok, _id]); // no borrow -> check floor
            array_push(_list, ["lda_imm", _top_stop,  _id]); // underflow -> clamp
            array_push(_list, ["jmp_abs", _lbl_ydone, _id]);
            array_push(_list, ["label",   _lbl_yn_ok, _id]);
            array_push(_list, ["cmp_imm", _top_stop,  _id]);
            var _lbl_yn_ok2 = _sp + "ynok2";
            array_push(_list, ["bcs",     _lbl_yn_ok2, _id]); // new Y >= top_stop -> fine
            array_push(_list, ["lda_imm", _top_stop,   _id]); // clamp
            array_push(_list, ["label",   _lbl_yn_ok2, _id]);
        }
        array_push(_list, ["sta_abs", _vy,  _id]);
        array_push(_list, ["label", _lbl_ydone, _id]);
        array_push(_list, ["label", _lbl_yskip, _id]);

        // ---- write dist out var ----
        if (_dist_uv == 1 && _dist_addr != 0) {
            array_push(_list, ["lda_zp",  _zp_dist, _id]);
            array_push(_list, ["sta_abs", _dist_addr, _id]);
        }

        // ===============================================================
        // 8-WAY ANGLE  (0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW, 255=at target)
        //   uses sgnx/sgny + |dx| vs |dy| magnitude compare for diagonals
        // ===============================================================
        if (_ang_uv == 1 && _ang_addr != 0) {
            var _aL = _sp + "a_";
            var _lbl_a_at   = _aL + "at";
            var _lbl_a_done = _aL + "done";

            // at target? (dxh==0 && dx==0 && dy==0) -> 255
            array_push(_list, ["lda_zp",  _zp_dxh,  _id]);
            array_push(_list, ["bne",     _aL + "nz", _id]);
            array_push(_list, ["lda_zp",  _zp_dx,   _id]);
            array_push(_list, ["bne",     _aL + "nz", _id]);
            array_push(_list, ["lda_zp",  _zp_dy,   _id]);
            array_push(_list, ["bne",     _aL + "nz", _id]);
            array_push(_list, ["lda_imm", 0xFF,     _id]);
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            array_push(_list, ["label",   _aL + "nz", _id]);

            // diagonal test: is the move diagonal? |dx| and |dy| both "significant".
            // Simple scheme: if dxh!=0 treat X as dominant axis (pure E/W by sign).
            // else compare |dx| vs |dy|:
            //   |dx| > |dy|*2  -> pure horizontal (E/W)
            //   |dy| > |dx|*2  -> pure vertical   (N/S)
            //   else            -> diagonal
            // (the *2 split keeps the 8 sectors roughly even)
            var _lbl_horiz = _aL + "h";
            var _lbl_vert  = _aL + "v";
            var _lbl_diag  = _aL + "dg";

            array_push(_list, ["lda_zp",  _zp_dxh,  _id]);
            array_push(_list, ["bne",     _lbl_horiz, _id]); // big dx -> horizontal

            // tmp = |dy|*2 (cap at 255) ; compare |dx| vs tmp
            array_push(_list, ["lda_zp",  _zp_dy,   _id]);
            array_push(_list, ["asl_a",   0,        _id]);   // *2
            array_push(_list, ["bcs",     _lbl_vert, _id]);  // overflowed -> dy huge -> vertical
            array_push(_list, ["sta_zp",  0x0C,     _id]);   // tmp = 2*dy
            array_push(_list, ["lda_zp",  _zp_dx,   _id]);
            array_push(_list, ["cmp_zp",  0x0C,     _id]);
            array_push(_list, ["bcs",     _lbl_horiz, _id]); // dx >= 2*dy -> horizontal

            // tmp = |dx|*2 ; compare |dy| vs tmp
            array_push(_list, ["lda_zp",  _zp_dx,   _id]);
            array_push(_list, ["asl_a",   0,        _id]);
            array_push(_list, ["bcs",     _lbl_vert, _id]);
            array_push(_list, ["sta_zp",  0x0C,     _id]);
            array_push(_list, ["lda_zp",  _zp_dy,   _id]);
            array_push(_list, ["cmp_zp",  0x0C,     _id]);
            array_push(_list, ["bcs",     _lbl_vert, _id]); // dy >= 2*dx -> vertical
            array_push(_list, ["jmp_abs", _lbl_diag, _id]);

            // ---- HORIZONTAL: sgnx 0 -> E(2), 1 -> W(6) ----
            array_push(_list, ["label",   _lbl_horiz, _id]);
            array_push(_list, ["lda_zp",  _zp_sgnx, _id]);
            array_push(_list, ["bne",     _aL + "hw", _id]);
            array_push(_list, ["lda_imm", 0x02,     _id]); // E
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            array_push(_list, ["label",   _aL + "hw", _id]);
            array_push(_list, ["lda_imm", 0x06,     _id]); // W
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);

            // ---- VERTICAL: sgny 0 -> S(4), 1 -> N(0) ----
            array_push(_list, ["label",   _lbl_vert, _id]);
            array_push(_list, ["lda_zp",  _zp_sgny, _id]);
            array_push(_list, ["bne",     _aL + "vn", _id]);
            array_push(_list, ["lda_imm", 0x04,     _id]); // S (dy positive = down)
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            array_push(_list, ["label",   _aL + "vn", _id]);
            array_push(_list, ["lda_imm", 0x00,     _id]); // N
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);

            // ---- DIAGONAL: pick by (sgnx,sgny) ----
            //  sgnx0 sgny0 -> SE(3) ; sgnx0 sgny1 -> NE(1)
            //  sgnx1 sgny0 -> SW(5) ; sgnx1 sgny1 -> NW(7)
            array_push(_list, ["label",   _lbl_diag, _id]);
            array_push(_list, ["lda_zp",  _zp_sgnx, _id]);
            array_push(_list, ["bne",     _aL + "dxl", _id]);
            // sgnx==0 (east side)
            array_push(_list, ["lda_zp",  _zp_sgny, _id]);
            array_push(_list, ["bne",     _aL + "ne", _id]);
            array_push(_list, ["lda_imm", 0x03,     _id]); // SE
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            array_push(_list, ["label",   _aL + "ne", _id]);
            array_push(_list, ["lda_imm", 0x01,     _id]); // NE
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            // sgnx==1 (west side)
            array_push(_list, ["label",   _aL + "dxl", _id]);
            array_push(_list, ["lda_zp",  _zp_sgny, _id]);
            array_push(_list, ["bne",     _aL + "nw", _id]);
            array_push(_list, ["lda_imm", 0x05,     _id]); // SW
            array_push(_list, ["jmp_abs", _lbl_a_done, _id]);
            array_push(_list, ["label",   _aL + "nw", _id]);
            array_push(_list, ["lda_imm", 0x07,     _id]); // NW

            array_push(_list, ["label",   _lbl_a_done, _id]);
            array_push(_list, ["sta_abs", _ang_addr, _id]);
        }
    }

    break;
}



// =============================================================
// MACRO_SPR_EXPAND - X/Y expand toggles ($D01D / $D017)
// =============================================================

case "MACRO_SPR_EXPAND": {
    var _x_mask = real(_curr.instructions[0][1]);
    var _y_mask = real(_curr.instructions[0][2]);
    var _id     = _curr;
    // ---- X EXPAND ($D01D) ----
    // write the mask directly so unchecked bits clear and checked bits set
    array_push(_list, ["lda_imm", _x_mask & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xD01D, _id]);
    // ---- Y EXPAND ($D017) ----
    array_push(_list, ["lda_imm", _y_mask & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xD017, _id]);
} break;
	
// =============================================================
// MACRO_MOVE — UNISON SPRITE MOVEMENT (MINIMAL BYTE VERSION)
// =============================================================	
	
case "MACRO_MOVE": {
    var _mask     = real(_curr.instructions[0][1]);
    var _dx_lit   = real(_curr.instructions[0][2]);
    var _dy_lit   = real(_curr.instructions[0][3]);
    var _widex    = real(_curr.instructions[0][4]);
    var _dx_mod   = real(_curr.instructions[0][5]);
    var _dy_mod   = real(_curr.instructions[0][6]);
    var _dx_uv    = (array_length(_curr.instructions[0]) > 7 && is_real(_curr.instructions[0][7])) ? real(_curr.instructions[0][7]) : 0;
    var _dx_vnm   = (array_length(_curr.instructions[0]) > 8) ? string(_curr.instructions[0][8]) : "";
    var _dy_uv    = (array_length(_curr.instructions[0]) > 9 && is_real(_curr.instructions[0][9])) ? real(_curr.instructions[0][9]) : 0;
    var _dy_vnm   = (array_length(_curr.instructions[0]) > 10) ? string(_curr.instructions[0][10]) : "";
    var _id       = _curr;

    var _left_stop  = (array_length(_curr.instructions[0]) > 11 && is_real(_curr.instructions[0][11])) ? real(_curr.instructions[0][11]) : 25;
    var _right_stop = (array_length(_curr.instructions[0]) > 12 && is_real(_curr.instructions[0][12])) ? real(_curr.instructions[0][12]) : 320;
    if (_widex == 0 && _right_stop > 255) _right_stop = 255;
    var _top_stop   = (array_length(_curr.instructions[0]) > 13 && is_real(_curr.instructions[0][13])) ? real(_curr.instructions[0][13]) : 51;
    var _bot_stop   = (array_length(_curr.instructions[0]) > 14 && is_real(_curr.instructions[0][14])) ? real(_curr.instructions[0][14]) : 229;

    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    var _leader = -1;
    for (var _si = 0; _si < 8; _si++) {
        if (_mask & _bit_values[_si]) { _leader = _si; break; }
    }
    if (_leader == -1) break;

    var _lead_xreg = 0xD000 + (_leader * 2);
    var _lead_yreg = 0xD001 + (_leader * 2);
    var _pfx = "mm" + string(_leader) + "_" + string(real(_id)) + "_";

    // Resolve var addresses if in var mode
    var _dx_var_addr = 0;
    var _dy_var_addr = 0;
    if (_dx_uv == 1 && _dx_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _dx_vnm)) {
            _dx_var_addr = ds_map_find_value(global.named_loc_map, _dx_vnm);
        }
        if (_dx_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dx_vnm) {
                    _dx_var_addr = pc_address;
                    break;
                }
            }
        }
        if (_dx_var_addr == 0) show_debug_message("MACRO_MOVE WARNING: DX var '" + _dx_vnm + "' not resolved.");
    }
    if (_dy_uv == 1 && _dy_vnm != "") {
        if (ds_map_exists(global.named_loc_map, _dy_vnm)) {
            _dy_var_addr = ds_map_find_value(global.named_loc_map, _dy_vnm);
        }
        if (_dy_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dy_vnm) {
                    _dy_var_addr = pc_address;
                    break;
                }
            }
        }
        if (_dy_var_addr == 0) show_debug_message("MACRO_MOVE WARNING: DY var '" + _dy_vnm + "' not resolved.");
    }

    // Effective values for "should we emit" check
    var _dx_active = (_dx_uv == 1) ? (_dx_var_addr != 0) : (_dx_lit != 0);
    var _dy_active = (_dy_uv == 1) ? (_dy_var_addr != 0) : (_dy_lit != 0);

    // --- X MOVEMENT ---
    if (_dx_active || _widex == 1) {
        var _lbl_dn = _pfx + "xdn";

        if (_dx_uv == 1 && _dx_var_addr != 0) {
            // ===== VAR MODE =====
            // Load var, check sign, branch to neg/pos path
            var _lbl_neg  = _pfx + "xneg";
            var _lbl_done = _pfx + "xvdone";

            // Boundary checks done per-sprite-direction at runtime
            // STOP mode: peek leader X, compare against bound based on var sign
            if (_dx_mod == 1) {
                var _lbl_chk_neg = _pfx + "xcn";
                var _lbl_chk_end = _pfx + "xce";
                array_push(_list, ["lda_abs", _dx_var_addr, _id]);
                array_push(_list, ["bmi",     _lbl_chk_neg, _id]);
                // Positive: check right wall
                if (_widex) {
                    var _lbl_no_stop = _pfx + "xns";
                    array_push(_list, ["lda_abs", 0xD010, _id]);
                    array_push(_list, ["and_imm", _bit_values[_leader], _id]);
                    array_push(_list, ["beq", _lbl_no_stop, _id]);
                    array_push(_list, ["lda_abs", _lead_xreg, _id]);
                    array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                    array_push(_list, ["bcs", _lbl_dn, _id]);
                    array_push(_list, ["label", _lbl_no_stop, _id]);
                } else {
                    array_push(_list, ["lda_abs", _lead_xreg, _id]);
                    array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                    array_push(_list, ["bcs", _lbl_dn, _id]);
                }
                array_push(_list, ["jmp_abs", _lbl_chk_end, _id]);
                array_push(_list, ["label",   _lbl_chk_neg, _id]);
                // Negative: check left wall
                if (_widex) {
                    var _lbl_no_stop_l = _pfx + "xnsl";
                    array_push(_list, ["lda_abs", 0xD010, _id]);
                    array_push(_list, ["and_imm", _bit_values[_leader], _id]);
                    array_push(_list, ["bne", _lbl_no_stop_l, _id]);
                    array_push(_list, ["lda_abs", _lead_xreg, _id]);
                    array_push(_list, ["cmp_imm", _left_stop, _id]);
                    array_push(_list, ["bcc", _lbl_dn, _id]);
                    array_push(_list, ["label", _lbl_no_stop_l, _id]);
                } else {
                    array_push(_list, ["lda_abs", _lead_xreg, _id]);
                    array_push(_list, ["cmp_imm", _left_stop, _id]);
                    array_push(_list, ["bcc", _lbl_dn, _id]);
                }
                array_push(_list, ["label", _lbl_chk_end, _id]);
            }

            // Re-load var, dispatch on sign
            array_push(_list, ["lda_abs", _dx_var_addr, _id]);
            array_push(_list, ["bmi",     _lbl_neg,     _id]);

            // ----- POSITIVE PATH (A holds +delta) -----
            for (var _si = 0; _si < 8; _si++) {
                if (_mask & _bit_values[_si]) {
                    var _reg = 0xD000 + (_si * 2);
                    var _skip_flip = _pfx + "sfp" + string(_si);
                    array_push(_list, ["clc",     0,            _id]);
                    array_push(_list, ["adc_abs", _reg,         _id]); // A = delta + sprite_x
                    array_push(_list, ["sta_abs", _reg,         _id]);
                    if (_widex) {
                        array_push(_list, ["bcc",     _skip_flip, _id]);
                        array_push(_list, ["pha",     0,          _id]); // preserve A across $D010 work
                        array_push(_list, ["lda_abs", 0xD010,     _id]);
                        array_push(_list, ["eor_imm", _bit_values[_si], _id]);
                        array_push(_list, ["sta_abs", 0xD010,     _id]);
                        array_push(_list, ["pla",     0,          _id]);
                        array_push(_list, ["label",   _skip_flip, _id]);
                    }
                    // Re-load var for next sprite (delta was clobbered by ADC sum)
                    array_push(_list, ["lda_abs", _dx_var_addr, _id]);
                }
            }
            array_push(_list, ["jmp_abs", _lbl_done, _id]);

            // ----- NEGATIVE PATH (A holds negative two's-complement delta) -----
            array_push(_list, ["label", _lbl_neg, _id]);
            // Convert to positive magnitude in X for SBC use
            array_push(_list, ["eor_imm", 0xFF, _id]);
            array_push(_list, ["clc",     0,    _id]);
            array_push(_list, ["adc_imm", 1,    _id]); // A = abs(delta)
            array_push(_list, ["tax",     0,    _id]); // X = abs(delta) for reuse

            for (var _si = 0; _si < 8; _si++) {
                if (_mask & _bit_values[_si]) {
                    var _reg = 0xD000 + (_si * 2);
                    var _skip_flip2 = _pfx + "sfn" + string(_si);
                    array_push(_list, ["lda_abs", _reg, _id]);
                    array_push(_list, ["sec",     0,    _id]);
                    array_push(_list, ["stx_zp",  0xFB, _id]); // scratch zp for SBC source — adjust if you have a reserved scratch
                    array_push(_list, ["sbc_zp",  0xFB, _id]);
                    array_push(_list, ["sta_abs", _reg, _id]);
                    if (_widex) {
                        array_push(_list, ["bcs",     _skip_flip2, _id]);
                        array_push(_list, ["lda_abs", 0xD010,      _id]);
                        array_push(_list, ["eor_imm", _bit_values[_si], _id]);
                        array_push(_list, ["sta_abs", 0xD010,      _id]);
                        array_push(_list, ["label",   _skip_flip2, _id]);
                    }
                }
            }
            array_push(_list, ["label", _lbl_done, _id]);

        } else if (_dx_lit != 0 || _widex == 1) {
            // ===== LITERAL MODE (original logic preserved) =====
            var _abs_dx = abs(_dx_lit);

            if (_dx_mod == 1 && _dx_lit != 0) {
                array_push(_list, ["lda_abs", _lead_xreg, _id]);
                if (_dx_lit > 0) {
                    if (_widex) {
                        var _lbl_no_stop = _pfx + "xns";
                        array_push(_list, ["lda_abs", 0xD010, _id]);
                        array_push(_list, ["and_imm", _bit_values[_leader], _id]);
                        array_push(_list, ["beq", _lbl_no_stop, _id]);
                        array_push(_list, ["lda_abs", _lead_xreg, _id]);
                        array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                        array_push(_list, ["bcs", _lbl_dn, _id]);
                        array_push(_list, ["label", _lbl_no_stop, _id]);
                    } else {
                        array_push(_list, ["cmp_imm", _right_stop & 0xFF, _id]);
                        array_push(_list, ["bcs", _lbl_dn, _id]);
                    }
                } else {
                    if (_widex) {
                        var _lbl_no_stop_l = _pfx + "xnsl";
                        array_push(_list, ["lda_abs", 0xD010, _id]);
                        array_push(_list, ["and_imm", _bit_values[_leader], _id]);
                        array_push(_list, ["bne", _lbl_no_stop_l, _id]);
                        array_push(_list, ["lda_abs", _lead_xreg, _id]);
                        array_push(_list, ["cmp_imm", _left_stop, _id]);
                        array_push(_list, ["bcc", _lbl_dn, _id]);
                        array_push(_list, ["label", _lbl_no_stop_l, _id]);
                    } else {
                        array_push(_list, ["cmp_imm", _left_stop, _id]);
                        array_push(_list, ["bcc", _lbl_dn, _id]);
                    }
                }
            }

            if (_dx_lit != 0) {
                for (var _si = 0; _si < 8; _si++) {
                    if (_mask & _bit_values[_si]) {
                        var _reg = 0xD000 + (_si * 2);
                        var _skip_flip = _pfx + "sf" + string(_si);
                        array_push(_list, ["lda_abs", _reg, _id]);
                        if (_dx_lit > 0) {
                            array_push(_list, ["clc", 0, _id]);
                            array_push(_list, ["adc_imm", _abs_dx, _id]);
                            array_push(_list, ["sta_abs", _reg, _id]);
                            if (_widex) {
                                array_push(_list, ["bcc", _skip_flip, _id]);
                            }
                        } else {
                            array_push(_list, ["sec", 0, _id]);
                            array_push(_list, ["sbc_imm", _abs_dx, _id]);
                            array_push(_list, ["sta_abs", _reg, _id]);
                            if (_widex) {
                                array_push(_list, ["bcs", _skip_flip, _id]);
                            }
                        }
                        if (_widex) {
                            array_push(_list, ["lda_abs", 0xD010, _id]);
                            array_push(_list, ["eor_imm", _bit_values[_si], _id]);
                            array_push(_list, ["sta_abs", 0xD010, _id]);
                            array_push(_list, ["label", _skip_flip, _id]);
                        }
                    }
                }
            }
        }
        array_push(_list, ["label", _lbl_dn, _id]);
    }

    // --- Y MOVEMENT ---
    if (_dy_active) {
        var _lbl_ydn = _pfx + "ydn";

        if (_dy_uv == 1 && _dy_var_addr != 0) {
            // ===== VAR MODE =====
            var _lbl_yneg  = _pfx + "yneg";
            var _lbl_ydone = _pfx + "yvdone";

            if (_dy_mod == 1) {
                var _lbl_ychk_neg = _pfx + "ycn";
                var _lbl_ychk_end = _pfx + "yce";
                array_push(_list, ["lda_abs", _dy_var_addr, _id]);
                array_push(_list, ["bmi",     _lbl_ychk_neg, _id]);
                array_push(_list, ["lda_abs", _lead_yreg, _id]);
                array_push(_list, ["cmp_imm", _bot_stop, _id]);
                array_push(_list, ["bcs",     _lbl_ydn, _id]);
                array_push(_list, ["jmp_abs", _lbl_ychk_end, _id]);
                array_push(_list, ["label",   _lbl_ychk_neg, _id]);
                array_push(_list, ["lda_abs", _lead_yreg, _id]);
                array_push(_list, ["cmp_imm", _top_stop, _id]);
                array_push(_list, ["bcc",     _lbl_ydn, _id]);
                array_push(_list, ["label",   _lbl_ychk_end, _id]);
            }

            array_push(_list, ["lda_abs", _dy_var_addr, _id]);
            array_push(_list, ["bmi",     _lbl_yneg,    _id]);

            // POSITIVE PATH
            for (var _sy = 0; _sy < 8; _sy++) {
                if (_mask & _bit_values[_sy]) {
                    var _y_reg = 0xD001 + (_sy * 2);
                    array_push(_list, ["clc",     0,            _id]);
                    array_push(_list, ["adc_abs", _y_reg,       _id]);
                    array_push(_list, ["sta_abs", _y_reg,       _id]);
                    array_push(_list, ["lda_abs", _dy_var_addr, _id]);
                }
            }
            array_push(_list, ["jmp_abs", _lbl_ydone, _id]);

            // NEGATIVE PATH
            array_push(_list, ["label",   _lbl_yneg, _id]);
            array_push(_list, ["eor_imm", 0xFF, _id]);
            array_push(_list, ["clc",     0,    _id]);
            array_push(_list, ["adc_imm", 1,    _id]);
            array_push(_list, ["tax",     0,    _id]);
            for (var _sy = 0; _sy < 8; _sy++) {
                if (_mask & _bit_values[_sy]) {
                    var _y_reg = 0xD001 + (_sy * 2);
                    array_push(_list, ["lda_abs", _y_reg, _id]);
                    array_push(_list, ["sec",     0,      _id]);
                    array_push(_list, ["stx_zp",  0xFB,   _id]);
                    array_push(_list, ["sbc_zp",  0xFB,   _id]);
                    array_push(_list, ["sta_abs", _y_reg, _id]);
                }
            }
            array_push(_list, ["label", _lbl_ydone, _id]);

        } else if (_dy_lit != 0) {
            // ===== LITERAL MODE (original) =====
            var _abs_dy = abs(_dy_lit);
            if (_dy_mod == 1) {
                array_push(_list, ["lda_abs", _lead_yreg, _id]);
                if (_dy_lit > 0) {
                    array_push(_list, ["cmp_imm", _bot_stop, _id]);
                    array_push(_list, ["bcs", _lbl_ydn, _id]);
                } else {
                    array_push(_list, ["cmp_imm", _top_stop, _id]);
                    array_push(_list, ["bcc", _lbl_ydn, _id]);
                }
            }
            for (var _sy = 0; _sy < 8; _sy++) {
                if (_mask & _bit_values[_sy]) {
                    var _y_reg = 0xD001 + (_sy * 2);
                    array_push(_list, ["lda_abs", _y_reg, _id]);
                    if (_dy_lit > 0) {
                        array_push(_list, ["clc", 0, _id]);
                        array_push(_list, ["adc_imm", _abs_dy, _id]);
                    } else {
                        array_push(_list, ["sec", 0, _id]);
                        array_push(_list, ["sbc_imm", _abs_dy, _id]);
                    }
                    array_push(_list, ["sta_abs", _y_reg, _id]);
                }
            }
        }
        array_push(_list, ["label", _lbl_ydn, _id]);
    }
    break;
}

/// END OF MACRO MOVE
				
// --------------------------------------------------------
// GET_VAR - Load UV_ variable, or BYTE_DATA asset byte, into registers
// --------------------------------------------------------
case "GET_VAR": {
    var _id = _curr;
    // Backfill old saves
    while (array_length(_curr.instructions[0]) < 8) array_push(_curr.instructions[0], "");
    var _src_mode = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0;

    if (_src_mode == 1) {
        // ===== ASSET MODE =====
        var _asset_name = string(_curr.instructions[0][3]);
        var _off_mode   = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) : 0;
        var _off_lit    = is_real(_curr.instructions[0][5]) ? real(_curr.instructions[0][5]) : 0;
        var _off_var    = string(_curr.instructions[0][6]);

        // Resolve asset base address (matches memory bar / compile placement)
        var _abase = 0;
        if (_asset_name != "" && instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = _am.asset_list[| _ai];
                if (_a.type == "BYTE_DATA" && _a.name == _asset_name) { _abase = _a.address; break; }
            }
        }
        if (_abase == 0) show_debug_message("GET_VAR WARNING: BYTE_DATA asset '" + _asset_name + "' not resolved.");

        if (_off_mode == 2) {
            // Offset via X register
            array_push(_list, ["lda_abx", _abase, _id]);
        } else if (_off_mode == 3) {
            // Offset via Y register
            array_push(_list, ["lda_aby", _abase, _id]);
        } else if (_off_mode == 1) {
            // Offset via UV var — stage into X, then lda_abx
            var _ovaddr = 0;
            if (ds_map_exists(global.named_loc_map, _off_var)) {
                _ovaddr = ds_map_find_value(global.named_loc_map, _off_var);
            }
            if (_ovaddr == 0) show_debug_message("GET_VAR WARNING: offset var '" + _off_var + "' not resolved.");
            array_push(_list, ["ldx_abs", _ovaddr, _id]);
            array_push(_list, ["lda_abx", _abase,  _id]);
        } else {
            // No / literal offset — fold literal into the absolute address
            array_push(_list, ["lda_abs", _abase + _off_lit, _id]);
        }
        // Optional destination var — store A into named UV/HW location
        var _dest_var = string(_curr.instructions[0][7]);
        if (_dest_var != "") {
            var _daddr = 0;
            if (ds_map_exists(global.named_loc_map, _dest_var)) {
                _daddr = ds_map_find_value(global.named_loc_map, _dest_var);
            }
            if (_daddr == 0) show_debug_message("GET_VAR WARNING: dest var '" + _dest_var + "' not resolved.");
            array_push(_list, ["sta_abs", _daddr, _id]);
        }
    } else {
        // ===== NAMED VAR MODE (original behaviour) =====
        var _var_name = string(_curr.instructions[0][1]);
        var _addr     = 0;
        var _size     = 1;
        var _is_bcd   = false;
        // Stage 1: resolve address from named_loc_map (covers HW_ and UV_)
        if (ds_map_exists(global.named_loc_map, _var_name)) {
            _addr = ds_map_find_value(global.named_loc_map, _var_name);
        }
        // Stage 2: fall back to scanning workspace NAMED_LOC nodes (legacy UV_)
        if (_addr == 0) {
            var _var_name_find = _var_name;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                    other._addr = pc_address;
                    break;
                }
            }
        }
        // Stage 3: size and encoding from meta
        var _m = scr_nloc_find_meta(_var_name);
        if (_m != undefined) {
            _size = _m.size;
            var _encoding = variable_struct_exists(_m, "encoding") ? _m.encoding : "byte";
            _is_bcd = (_encoding == "bcd" || _encoding == "bcd2" || _encoding == "bcd3");
        }
        if (_addr == 0) show_debug_message("GET_VAR WARNING: '" + _var_name + "' not resolved.");
        array_push(_list, ["lda_abs", _addr, _id]);
        if (_size >= 2) array_push(_list, ["ldx_abs", _addr + 1, _id]);
        if (_size >= 3) array_push(_list, ["ldy_abs", _addr + 2, _id]);
    }
} break;

// --------------------------------------------------------
// SET_VAR - Store value into UV_ variable
// --------------------------------------------------------
case "SET_VAR": {
    var _id       = _curr;
    var _var_name = string(_curr.instructions[0][1]);
    var _value    = (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2])) ? real(_curr.instructions[0][2]) : 0;
    var _mode     = (array_length(_curr.instructions[0]) > 3 && is_real(_curr.instructions[0][3])) ? real(_curr.instructions[0][3]) : 0;
    var _sign     = (array_length(_curr.instructions[0]) > 4 && is_real(_curr.instructions[0][4])) ? real(_curr.instructions[0][4]) : 0;
    var _addr     = 0;
    var _size     = 1;
    var _is_bcd   = false;

    // Stage 1: resolve address from named_loc_map (covers HW_ and UV_)
    if (ds_map_exists(global.named_loc_map, _var_name)) {
        _addr = ds_map_find_value(global.named_loc_map, _var_name);
    }

    // Stage 2: if still zero, fall back to scanning workspace NAMED_LOC nodes (legacy UV_)
    if (_addr == 0) {
        var _var_name_find = _var_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                other._addr = pc_address;
                break;
            }
        }
    }

    // Stage 3: get size and encoding from meta (works for both HW_ and UV_)
    var _m = scr_nloc_find_meta(_var_name);
    if (_m != undefined) {
        _size = _m.size;
        var _encoding = variable_struct_exists(_m, "encoding") ? _m.encoding : "byte";
        _is_bcd = (_encoding == "bcd" || _encoding == "bcd2" || _encoding == "bcd3");
    }

    if (_addr == 0) show_debug_message("SET_VAR WARNING: '" + _var_name + "' not resolved.");

    // ------------------------------------------------
    // PTR MODE — store a byte at the *resolved address* held by dest word
    // dest var holds a 16-bit pointer (e.g. $C001 = $0504); we write a byte to $0504.
    // Uses ZP scratch $FB/$FC for STA (zp),Y.
    // ------------------------------------------------
    var _src_mode = (array_length(_curr.instructions[0]) > 5 && is_real(_curr.instructions[0][5])) ? real(_curr.instructions[0][5]) : 0;
    var _offset_x = (array_length(_curr.instructions[0]) > 8 && is_real(_curr.instructions[0][8])) ? real(_curr.instructions[0][8]) : 0;
    if (_src_mode >= 3) {
        // ------------------------------------------------
        // REGISTER MODE — store A / X / Y straight to dest address
        // 3 = A, 4 = X, 5 = Y
        // A supports ,X offset; X and Y do not (no abs-indexed STX/STY).
        // ------------------------------------------------
        if (_src_mode == 3) {
            if (_offset_x == 1) {
                array_push(_list, ["sta_abx", _addr, _id]);
            } else {
                array_push(_list, ["sta_abs", _addr, _id]);
            }
        } else if (_src_mode == 4) {
            array_push(_list, ["stx_abs", _addr, _id]);
        } else {
            array_push(_list, ["sty_abs", _addr, _id]);
        }
    } else if (_src_mode == 2) {
        var _ptr_byte_mode = (array_length(_curr.instructions[0]) > 7 && is_real(_curr.instructions[0][7])) ? real(_curr.instructions[0][7]) : 0;
        var _ZP_LO = 0xFB;
        var _ZP_HI = 0xFC;
        // Load pointer (word at dest addr) into ZP scratch
        array_push(_list, ["lda_abs", _addr,        _id]);
        array_push(_list, ["sta_zp",  _ZP_LO,       _id]);
        array_push(_list, ["lda_abs", _addr + 1,    _id]);
        array_push(_list, ["sta_zp",  _ZP_HI,       _id]);
        // Load the byte to store
        if (_ptr_byte_mode == 1) {
            var _pb_name = (array_length(_curr.instructions[0]) > 6) ? string(_curr.instructions[0][6]) : "";
            var _pb_addr = 0;
            if (ds_map_exists(global.named_loc_map, _pb_name)) {
                _pb_addr = ds_map_find_value(global.named_loc_map, _pb_name);
            }
            if (_pb_addr == 0) {
                var _pb_find = _pb_name;
                with (obj_c64_node) {
                    if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _pb_find) {
                        other._pb_addr = pc_address;
                        break;
                    }
                }
            }
            if (_pb_addr == 0) show_debug_message("SET_VAR(PTR) WARNING: byte src '" + _pb_name + "' not resolved.");
            array_push(_list, ["lda_abs", _pb_addr, _id]);
        } else {
            array_push(_list, ["lda_imm", _value & 0xFF, _id]);
        }
        // STA (zp),Y  with Y=0
        array_push(_list, ["ldy_imm", 0x00,   _id]);
        array_push(_list, ["sta_izy", _ZP_LO, _id]);
    } else if (_src_mode == 1) {
        var _src_name = (array_length(_curr.instructions[0]) > 6) ? string(_curr.instructions[0][6]) : "";
        var _src_addr = 0;
        if (ds_map_exists(global.named_loc_map, _src_name)) {
            _src_addr = ds_map_find_value(global.named_loc_map, _src_name);
        }
        if (_src_addr == 0) {
            var _src_find = _src_name;
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _src_find) {
                    other._src_addr = pc_address;
                    break;
                }
            }
        }
        if (_src_addr == 0) show_debug_message("SET_VAR(VAR) WARNING: src '" + _src_name + "' not resolved.");
        array_push(_list, ["lda_abs", _src_addr, _id]);
        if (_offset_x == 1) {
            array_push(_list, ["sta_abx", _addr, _id]);
        } else {
            array_push(_list, ["sta_abs", _addr, _id]);
        }
    } else if (_mode == 0) {
        // ------------------------------------------------
        // ABS MODE — set exact value
        // ------------------------------------------------
		if (_is_bcd) {
            var _b0 = (_value % 100);
            var _b1 = (floor(_value / 100)   % 100);
            var _b2 = (floor(_value / 10000) % 100);
            _b0 = (floor(_b0 / 10) << 4) | (_b0 % 10);
            _b1 = (floor(_b1 / 10) << 4) | (_b1 % 10);
            _b2 = (floor(_b2 / 10) << 4) | (_b2 % 10);
            array_push(_list, ["lda_imm", _b0,        _id]);
            array_push(_list, ["sta_abs", _addr,      _id]);
            array_push(_list, ["lda_imm", _b1,        _id]);
            array_push(_list, ["sta_abs", _addr + 1,  _id]);
            array_push(_list, ["lda_imm", _b2,        _id]);
            array_push(_list, ["sta_abs", _addr + 2,  _id]);
        } else {
            // Binary byte/word
            // Offset ,X only applies to single-byte vars (word/BCD write multiple
            // addresses, so indexing them is hidden in the UI and ignored here).
            if (_offset_x == 1 && _size < 2) {
                array_push(_list, ["lda_imm", _value & 0xFF, _id]);
                array_push(_list, ["sta_abx", _addr,         _id]);
            } else {
                array_push(_list, ["lda_imm", _value & 0xFF,        _id]);
                array_push(_list, ["sta_abs", _addr,                _id]);
                if (_size >= 2) {
                    array_push(_list, ["ldx_imm", (_value >> 8) & 0xFF, _id]);
                    array_push(_list, ["stx_abs", _addr + 1,            _id]);
                }
                if (_size >= 3) {
                    array_push(_list, ["ldy_imm", (_value >> 16) & 0xFF, _id]);
                    array_push(_list, ["sty_abs", _addr + 2,             _id]);
                }
            }
        }

    } else if (_sign == 0) {
        // ------------------------------------------------
        // REL POS — add offset, clamp to max
        // ------------------------------------------------
        if (_is_bcd) {
            var _o0 = (_value % 100);
            var _o1 = (floor(_value / 100)   % 100);
            var _o2 = (floor(_value / 10000) % 100);
            _o0 = (floor(_o0 / 10) << 4) | (_o0 % 10);
            _o1 = (floor(_o1 / 10) << 4) | (_o1 % 10);
            _o2 = (floor(_o2 / 10) << 4) | (_o2 % 10);
            var _clamp_label = "sv_pmx_" + string(real(_id));
            array_push(_list, ["sed",     0,             _id]);
            array_push(_list, ["clc",     0,             _id]);
            array_push(_list, ["lda_abs", _addr,         _id]);
            array_push(_list, ["adc_imm", _o0,           _id]);
            array_push(_list, ["sta_abs", _addr,         _id]);
            array_push(_list, ["lda_abs", _addr + 1,     _id]);
            array_push(_list, ["adc_imm", _o1,           _id]);
            array_push(_list, ["sta_abs", _addr + 1,     _id]);
            array_push(_list, ["lda_abs", _addr + 2,     _id]);
            array_push(_list, ["adc_imm", _o2,           _id]);
            array_push(_list, ["bcc",     _clamp_label,  _id]);
            array_push(_list, ["lda_imm", 0x99,          _id]);
            array_push(_list, ["sta_abs", _addr,         _id]);
            array_push(_list, ["sta_abs", _addr + 1,     _id]);
            array_push(_list, ["sta_abs", _addr + 2,     _id]);
            array_push(_list, ["label",   _clamp_label       ]);
            array_push(_list, ["sta_abs", _addr + 2,     _id]);
            array_push(_list, ["cld",     0,             _id]);
        } else if (_size == 2) {
            var _clamp_label = "sv_pwx_" + string(real(_id));
            array_push(_list, ["clc",     0,                       _id]);
            array_push(_list, ["lda_abs", _addr,                   _id]);
            array_push(_list, ["adc_imm", _value & 0xFF,           _id]);
            array_push(_list, ["sta_abs", _addr,                   _id]);
            array_push(_list, ["lda_abs", _addr + 1,               _id]);
            array_push(_list, ["adc_imm", (_value >> 8) & 0xFF,    _id]);
            array_push(_list, ["bcc",     _clamp_label,            _id]);
            array_push(_list, ["lda_imm", 0xFF,                    _id]);
            array_push(_list, ["sta_abs", _addr,                   _id]);
            array_push(_list, ["sta_abs", _addr + 1,               _id]);
            array_push(_list, ["label",   _clamp_label                 ]);
            array_push(_list, ["sta_abs", _addr + 1,               _id]);
} else {
            if (_value <= 2) {
                repeat (_value) {
                    array_push(_list, ["inc_abs", _addr, _id]);
                }
            } else {
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abs", _addr,         _id]);
                array_push(_list, ["adc_imm", _value & 0xFF, _id]);
                array_push(_list, ["sta_abs", _addr,         _id]);
            }
        }

    } else {
        // ------------------------------------------------
        // REL NEG — subtract offset, clamp to 0
        // ------------------------------------------------
        if (_is_bcd) {
            var _o0 = (_value % 100);
            var _o1 = (floor(_value / 100)   % 100);
            var _o2 = (floor(_value / 10000) % 100);
            _o0 = (floor(_o0 / 10) << 4) | (_o0 % 10);
            _o1 = (floor(_o1 / 10) << 4) | (_o1 % 10);
            _o2 = (floor(_o2 / 10) << 4) | (_o2 % 10);
            var _clamp_label = "sv_nmn_"      + string(real(_id));
            var _done_label  = "sv_nmn_done_" + string(real(_id));
            array_push(_list, ["sed",     0,             _id]);
            array_push(_list, ["sec",     0,             _id]);
            array_push(_list, ["lda_abs", _addr,         _id]);
            array_push(_list, ["sbc_imm", _o0,           _id]);
            array_push(_list, ["sta_abs", _addr,         _id]);
            array_push(_list, ["lda_abs", _addr + 1,     _id]);
            array_push(_list, ["sbc_imm", _o1,           _id]);
            array_push(_list, ["sta_abs", _addr + 1,     _id]);
            array_push(_list, ["lda_abs", _addr + 2,     _id]);
            array_push(_list, ["sbc_imm", _o2,           _id]);
            array_push(_list, ["bcs",     _clamp_label,  _id]);
            array_push(_list, ["lda_imm", 0x00,          _id]);
            array_push(_list, ["sta_abs", _addr,         _id]);
            array_push(_list, ["sta_abs", _addr + 1,     _id]);
            array_push(_list, ["sta_abs", _addr + 2,     _id]);
            array_push(_list, ["cld",     0,             _id]);
            array_push(_list, ["jmp_abs", _done_label,   _id]);
            array_push(_list, ["label",   _clamp_label       ]);
            array_push(_list, ["sta_abs", _addr + 2,     _id]);
            array_push(_list, ["cld",     0,             _id]);
            array_push(_list, ["label",   _done_label        ]);
        } else if (_size == 2) {
            var _clamp_label = "sv_nwn_"      + string(real(_id));
            var _done_label  = "sv_nwn_done_" + string(real(_id));
            array_push(_list, ["sec",     0,                    _id]);
            array_push(_list, ["lda_abs", _addr,                _id]);
            array_push(_list, ["sbc_imm", _value & 0xFF,        _id]);
            array_push(_list, ["sta_abs", _addr,                _id]);
            array_push(_list, ["lda_abs", _addr + 1,            _id]);
            array_push(_list, ["sbc_imm", (_value >> 8) & 0xFF, _id]);
            array_push(_list, ["bcs",     _clamp_label,         _id]);
            array_push(_list, ["lda_imm", 0x00,                 _id]);
            array_push(_list, ["sta_abs", _addr,                _id]);
            array_push(_list, ["sta_abs", _addr + 1,            _id]);
            array_push(_list, ["jmp_abs", _done_label,          _id]);
            array_push(_list, ["label",   _clamp_label              ]);
            array_push(_list, ["sta_abs", _addr + 1,            _id]);
            array_push(_list, ["label",   _done_label               ]);
} else {
            if (_value <= 2) {
                repeat (_value) {
                    array_push(_list, ["dec_abs", _addr, _id]);
                }
            } else {
                array_push(_list, ["sec",     0,             _id]);
                array_push(_list, ["lda_abs", _addr,         _id]);
                array_push(_list, ["sbc_imm", _value & 0xFF, _id]);
                array_push(_list, ["sta_abs", _addr,         _id]);
            }
        }
    }
} break;

// --------------------------------------------------------
// INC_VAR - Increment a UV_ variable in memory
// --------------------------------------------------------
case "INC_VAR": {
    var _id       = _curr;
    var _var_name = string(_curr.instructions[0][1]);
    var _addr     = 0;
    var _size     = 1;
    var _is_bcd   = false;

    // Stage 1: resolve address from named_loc_map (covers HW_ and UV_)
    if (ds_map_exists(global.named_loc_map, _var_name)) {
        _addr = ds_map_find_value(global.named_loc_map, _var_name);
    }

    // Stage 2: if still zero, fall back to scanning workspace NAMED_LOC nodes (legacy UV_)
    if (_addr == 0) {
        var _var_name_find = _var_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                other._addr = pc_address;
                break;
            }
        }
    }

    // Stage 3: get size and encoding from meta (works for both HW_ and UV_)
    var _m = scr_nloc_find_meta(_var_name);
    if (_m != undefined) {
        _size = _m.size;
        var _encoding = variable_struct_exists(_m, "encoding") ? _m.encoding : "byte";
        _is_bcd = (_encoding == "bcd" || _encoding == "bcd2" || _encoding == "bcd3");
    }

    if (_addr == 0) show_debug_message("INC_VAR WARNING: '" + _var_name + "' not resolved.");

    if (_is_bcd) {
        // Decimal mode ripple carry ADC across all bytes.
        // After the top byte, if carry is still set the value overflowed
        // past its max (99 / 9999 / 999999) so clamp every byte to $99.
        var _inc_clamp = "inc_bcd_clamp_" + string(real(_id));
        array_push(_list, ["sed",     0,       _id]);
        array_push(_list, ["clc",     0,       _id]);
        array_push(_list, ["lda_abs", _addr,   _id]);
        array_push(_list, ["adc_imm", 0x01,    _id]);
        array_push(_list, ["sta_abs", _addr,   _id]);
        if (_size >= 2) {
            array_push(_list, ["lda_abs", _addr + 1, _id]);
            array_push(_list, ["adc_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _addr + 1, _id]);
        }
        if (_size >= 3) {
            array_push(_list, ["lda_abs", _addr + 2, _id]);
            array_push(_list, ["adc_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _addr + 2, _id]);
        }
        // Carry set here = overflow past max. Clamp all bytes to $99.
        array_push(_list, ["bcc",     _inc_clamp, _id]);
        array_push(_list, ["lda_imm", 0x99,       _id]);
        array_push(_list, ["sta_abs", _addr,      _id]);
        if (_size >= 2) {
            array_push(_list, ["sta_abs", _addr + 1, _id]);
        }
        if (_size >= 3) {
            array_push(_list, ["sta_abs", _addr + 2, _id]);
        }
        array_push(_list, ["label",   _inc_clamp]);
        array_push(_list, ["cld", 0, _id]);
    } else if (_size == 1) {
        array_push(_list, ["inc_abs", _addr, _id]);
    } else if (_size == 2) {
        // Word: only increment high byte if low byte wrapped to 0
        var _skip = "inc_skip_" + string(real(_id));
        array_push(_list, ["inc_abs", _addr,     _id]);
        array_push(_list, ["bne",     _skip,     _id]);
        array_push(_list, ["inc_abs", _addr + 1, _id]);
        array_push(_list, ["label",   _skip          ]);
    } else {
        // 3-byte: ripple carry through each byte only on wrap
        var _skip1 = "inc_skip1_" + string(real(_id));
        var _skip2 = "inc_skip2_" + string(real(_id));
        array_push(_list, ["inc_abs", _addr,     _id]);
        array_push(_list, ["bne",     _skip1,    _id]);
        array_push(_list, ["inc_abs", _addr + 1, _id]);
        array_push(_list, ["bne",     _skip2,    _id]);
        array_push(_list, ["inc_abs", _addr + 2, _id]);
        array_push(_list, ["label",   _skip2         ]);
        array_push(_list, ["label",   _skip1         ]);
    }
} break;

// --------------------------------------------------------
// DEC_VAR - Decrement a UV_ variable in memory
// --------------------------------------------------------
case "DEC_VAR": {
    var _id       = _curr;
    var _var_name = string(_curr.instructions[0][1]);
    var _addr     = 0;
    var _size     = 1;
    var _is_bcd   = false;

    // Stage 1: resolve address from named_loc_map (covers HW_ and UV_)
    if (ds_map_exists(global.named_loc_map, _var_name)) {
        _addr = ds_map_find_value(global.named_loc_map, _var_name);
    }

    // Stage 2: if still zero, fall back to scanning workspace NAMED_LOC nodes (legacy UV_)
    if (_addr == 0) {
        var _var_name_find = _var_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _var_name_find) {
                other._addr = pc_address;
                break;
            }
        }
    }

    // Stage 3: get size and encoding from meta (works for both HW_ and UV_)
    var _m = scr_nloc_find_meta(_var_name);
    if (_m != undefined) {
        _size = _m.size;
        var _encoding = variable_struct_exists(_m, "encoding") ? _m.encoding : "byte";
        _is_bcd = (_encoding == "bcd" || _encoding == "bcd2" || _encoding == "bcd3");
    }

    if (_addr == 0) show_debug_message("DEC_VAR WARNING: '" + _var_name + "' not resolved.");

    if (_is_bcd) {
        // Decimal mode ripple borrow SBC across all bytes
        array_push(_list, ["sed",     0,       _id]);
        array_push(_list, ["sec",     0,       _id]);
        array_push(_list, ["lda_abs", _addr,   _id]);
        array_push(_list, ["sbc_imm", 0x01,    _id]);
        array_push(_list, ["sta_abs", _addr,   _id]);
        if (_size >= 2) {
            array_push(_list, ["lda_abs", _addr + 1, _id]);
            array_push(_list, ["sbc_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _addr + 1, _id]);
        }
        if (_size >= 3) {
            array_push(_list, ["lda_abs", _addr + 2, _id]);
            array_push(_list, ["sbc_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _addr + 2, _id]);
        }
        array_push(_list, ["cld", 0, _id]);
    } else if (_size == 1) {
        array_push(_list, ["dec_abs", _addr, _id]);
    } else if (_size == 2) {
        // Word: only decrement high byte if low byte wrapped to $FF (was 0, now underflowed)
        var _skip = "dec_skip_" + string(real(_id));
        array_push(_list, ["lda_abs", _addr,     _id]);
        array_push(_list, ["bne",     _skip,     _id]);  // low byte != 0, no borrow needed
        array_push(_list, ["dec_abs", _addr + 1, _id]);  // low byte was 0, borrow from high
        array_push(_list, ["label",   _skip          ]);
        array_push(_list, ["dec_abs", _addr,     _id]);  // always decrement low byte
    } else {
        // 3-byte: ripple borrow through each byte only when needed
        var _skip1 = "dec_skip1_" + string(real(_id));
        var _skip2 = "dec_skip2_" + string(real(_id));
        array_push(_list, ["lda_abs", _addr,     _id]);
        array_push(_list, ["bne",     _skip1,    _id]);
        array_push(_list, ["lda_abs", _addr + 1, _id]);
        array_push(_list, ["bne",     _skip2,    _id]);
        array_push(_list, ["dec_abs", _addr + 2, _id]);
        array_push(_list, ["label",   _skip2         ]);
        array_push(_list, ["dec_abs", _addr + 1, _id]);
        array_push(_list, ["label",   _skip1         ]);
        array_push(_list, ["dec_abs", _addr,     _id]);
    }
} break;


// --------------------------------------------------------
// COPY_VAR - Copy SRC variable to DST variable
// --------------------------------------------------------
case "COPY_VAR": {
    var _id       = _curr;
    var _src_name = string(_curr.instructions[0][1]);
    var _dst_name = (array_length(_curr.instructions[0]) > 2) ? string(_curr.instructions[0][2]) : "";
    var _src_addr = 0;
    var _dst_addr = 0;
    var _src_size = 1;
    var _dst_size = 1;
    var _src_enc  = "byte";
    var _dst_enc  = "byte";

    // Resolve SRC address
    if (ds_map_exists(global.named_loc_map, _src_name)) {
        _src_addr = ds_map_find_value(global.named_loc_map, _src_name);
    }
    if (_src_addr == 0) {
        var _src_find = _src_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _src_find) {
                other._src_addr = pc_address;
                break;
            }
        }
    }

    // Resolve DST address
    if (ds_map_exists(global.named_loc_map, _dst_name)) {
        _dst_addr = ds_map_find_value(global.named_loc_map, _dst_name);
    }
    if (_dst_addr == 0) {
        var _dst_find = _dst_name;
        with (obj_c64_node) {
            if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dst_find) {
                other._dst_addr = pc_address;
                break;
            }
        }
    }

    // Get SRC meta
    var _ms = scr_nloc_find_meta(_src_name);
    if (_ms != undefined) {
        _src_size = _ms.size;
        if (variable_struct_exists(_ms, "encoding")) _src_enc = _ms.encoding;
    }

    // Get DST meta
    var _md = scr_nloc_find_meta(_dst_name);
    if (_md != undefined) {
        _dst_size = _md.size;
        if (variable_struct_exists(_md, "encoding")) _dst_enc = _md.encoding;
    }

    if (_src_addr == 0) show_debug_message("COPY_VAR WARNING: SRC '" + _src_name + "' not resolved.");
    if (_dst_addr == 0) show_debug_message("COPY_VAR WARNING: DST '" + _dst_name + "' not resolved.");

    // Copy as many bytes as the smaller side allows. BCD copies binary-byte-wise
    // because the encoding is just bit-layout within the byte.
    var _copy_bytes = min(_src_size, _dst_size);

    // Byte 0 (LSB) — always copied via A
    array_push(_list, ["lda_abs", _src_addr,     _id]);
    array_push(_list, ["sta_abs", _dst_addr,     _id]);

    if (_copy_bytes >= 2) {
        array_push(_list, ["ldx_abs", _src_addr + 1, _id]);
        array_push(_list, ["stx_abs", _dst_addr + 1, _id]);
    }
    if (_copy_bytes >= 3) {
        array_push(_list, ["ldy_abs", _src_addr + 2, _id]);
        array_push(_list, ["sty_abs", _dst_addr + 2, _id]);
    }

    // If DST is wider than SRC, zero-fill the high bytes
    if (_dst_size > _src_size) {
        array_push(_list, ["lda_imm", 0, _id]);
        if (_dst_size >= 2 && _src_size < 2) array_push(_list, ["sta_abs", _dst_addr + 1, _id]);
        if (_dst_size >= 3 && _src_size < 3) array_push(_list, ["sta_abs", _dst_addr + 2, _id]);
    }
} break;


// --------------------------------------------------------
// MACRO_IRQ_HANDLER
// Emits the unified table-driven raster IRQ shell.
// Reads all connected MACRO_IRQ nodes, sorts by raster line,
// builds irq_raster_table / irq_target_lo / irq_target_hi,
// and emits a self-modifying JSR dispatch handler.
// Vector mode: 0 = $0314/$0315 (Kernal), 1 = $FFFE/$FFFF (Direct)
// --------------------------------------------------------
case "MACRO_IRQ_HANDLER": {
    var _id   = _curr;
    var _mode = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) ? real(_id.instructions[0][1]) : 0;

    // Collect and sort MACRO_IRQ nodes by raster line
    var _irq_nodes = [];
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
            array_push(_irq_nodes, id);
    }
    array_sort(_irq_nodes, function(_a, _b) {
        var _ra = (array_length(_a.instructions[0]) > 1 && is_real(_a.instructions[0][1])) ? real(_a.instructions[0][1]) : 0x60;
        var _rb = (array_length(_b.instructions[0]) > 1 && is_real(_b.instructions[0][1])) ? real(_b.instructions[0][1]) : 0x60;
        return _ra - _rb;
    });
	var _irq_count = array_length(_irq_nodes);
    if (_irq_count == 0) break;
    if (_irq_count > 16) {
        show_debug_message("MACRO_IRQ_HANDLER WARNING: " + string(_irq_count) + " MACRO_IRQ nodes found — maximum is 16. Capping at 16. Remove " + string(_irq_count - 16) + " MACRO_IRQ node(s).");
        _irq_count = 16;
    }

    // Resolve SID play address if present
    var _has_sid_h   = false;
    var _play_addr_h = 0x1003;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected && org_parent == noone) {
            _has_sid_h = true;
            var _sn = string(instructions[0][1]);
            if (instance_exists(obj_asset_manager) && _sn != "") {
                var _am = obj_asset_manager;
                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                    var _a = ds_list_find_value(_am.asset_list, _ai);
                    if ((_a.type == "SID_MUSIC" || _a.type == "SID_SFX") && _a.name == _sn) {
                        _play_addr_h = variable_struct_exists(_a.meta, "sid_play_addr") ? real(_a.meta.sid_play_addr) : _a.address + 3;
                        break;
                    }
                }
            }
            break;
        }
    }

    var _p           = "irqh" + string(real(_id)) + "_";
    var _lbl_handler = _p + "handler";
    var _lbl_init    = _p + "init";
    var _lbl_skip    = _p + "skip";
    var _lbl_patch   = _p + "patch";
    var _lbl_raster  = _p + "raster_table";
    var _lbl_tgt_lo  = _p + "tgt_lo";
    var _lbl_tgt_hi  = _p + "tgt_hi";
    var _lbl_index   = _p + "index";
    var _lbl_nowrap  = _p + "nowrap";

    var _first_raster = (array_length(_irq_nodes[0].instructions[0]) > 1 && is_real(_irq_nodes[0].instructions[0][1]))
                      ? clamp(real(_irq_nodes[0].instructions[0][1]), 0, 255) : 0x60;

    var _first_cl = (array_length(_irq_nodes[0].instructions[0]) > 5 && string(_irq_nodes[0].instructions[0][5]) != "")
                  ? string(_irq_nodes[0].instructions[0][5])
                  : ("irq" + string(real(_irq_nodes[0])) + "_handler");

    // ── Inline: JSR init, JMP over subroutines ───────────────
    array_push(_list, ["jsr",     _lbl_init,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip,  _id]);

    // ════════════════════════════════════════════════════════
    // IRQ HANDLER
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_handler]);

    if (_mode == 1) {
        array_push(_list, ["pha",     0,        _id]);
        array_push(_list, ["txa",     0,        _id]);
        array_push(_list, ["pha",     0,        _id]);
        array_push(_list, ["tya",     0,        _id]);
        array_push(_list, ["pha",     0,        _id]);
    }

    // Ack VIC IRQ
    array_push(_list, ["lda_imm", 0xFF,         _id]);
    array_push(_list, ["sta_abs", 0xD019,       _id]);

    // Load index → X, patch JSR target from tables
    array_push(_list, ["ldx_lab", _lbl_index,   _id]);
    array_push(_list, ["lda_abx", _lbl_tgt_lo,  _id]);
    array_push(_list, ["sta_lab", _lbl_patch + "_lo", _id]);
    array_push(_list, ["lda_abx", _lbl_tgt_hi,  _id]);
    array_push(_list, ["sta_lab", _lbl_patch + "_hi", _id]);

    // Self-modifying JSR — operand bytes patched above
    array_push(_list, ["label",   _lbl_patch]);
    array_push(_list, ["byte",    0x20,          _id]);  // JSR opcode
    array_push(_list, ["label",   _lbl_patch + "_lo"]);
    array_push(_list, ["byte",    0x00,          _id]);  // lo — patched at runtime
    array_push(_list, ["label",   _lbl_patch + "_hi"]);
    array_push(_list, ["byte",    0x00,          _id]);  // hi — patched at runtime

    // Optional SID play on last slot
    if (_has_sid_h) {
        var _sid_slot     = _irq_count - 1;
        var _lbl_skip_sid = _p + "skipsid";
        array_push(_list, ["lda_imm", _sid_slot,          _id]);
        array_push(_list, ["cmp_lab", _lbl_index,         _id]);
        array_push(_list, ["bne",     _lbl_skip_sid,      _id]);
        array_push(_list, ["jsr",     real(_play_addr_h), _id]);
        array_push(_list, ["label",   _lbl_skip_sid]);
    }

    // Advance index, wrap at irq_count
    array_push(_list, ["ldx_lab", _lbl_index,   _id]);
    array_push(_list, ["inx",     0,            _id]);
    array_push(_list, ["cpx_imm", _irq_count,   _id]);
    array_push(_list, ["bne",     _lbl_nowrap,  _id]);
    array_push(_list, ["ldx_imm", 0,            _id]);
    array_push(_list, ["label",   _lbl_nowrap]);
    array_push(_list, ["stx_lab", _lbl_index,   _id]);

    // Set next raster trigger
    array_push(_list, ["lda_abx", _lbl_raster,  _id]);
    array_push(_list, ["sta_abs", 0xD012,        _id]);

    if (_mode == 1) {
        array_push(_list, ["pla",     0,        _id]);
        array_push(_list, ["tay",     0,        _id]);
        array_push(_list, ["pla",     0,        _id]);
        array_push(_list, ["tax",     0,        _id]);
        array_push(_list, ["pla",     0,        _id]);
        array_push(_list, ["rti",     0,        _id]);
    } else {
        array_push(_list, ["jmp_abs", 0xEA31,   _id]);
    }

    // ════════════════════════════════════════════════════════
    // INIT SUBROUTINE
    // ════════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_init]);

    // Disable CIA interrupts
    array_push(_list, ["lda_imm", 0x7F,         _id]);
    array_push(_list, ["sta_abs", 0xDC0D,       _id]);
    array_push(_list, ["sta_abs", 0xDD0D,       _id]);
    array_push(_list, ["lda_abs", 0xDC0D,       _id]);
    array_push(_list, ["lda_abs", 0xDD0D,       _id]);

    // VIC raster setup
    array_push(_list, ["lda_abs", 0xD011,       _id]);
    array_push(_list, ["and_imm", 0x7F,         _id]);
    array_push(_list, ["sta_abs", 0xD011,       _id]);
    array_push(_list, ["lda_imm", _first_raster, _id]);
    array_push(_list, ["sta_abs", 0xD012,       _id]);
    array_push(_list, ["lda_imm", 0xFF,         _id]);
    array_push(_list, ["sta_abs", 0xD019,       _id]);
    array_push(_list, ["lda_imm", 0x01,         _id]);
    array_push(_list, ["sta_abs", 0xD01A,       _id]);

    // Reset index
    array_push(_list, ["lda_imm", 0x00,         _id]);
    array_push(_list, ["sta_lab", _lbl_index,   _id]);

    // Wire vector
    if (_mode == 1) {
	    array_push(_list, ["lda_imm", 0x35,             _id]);
	    array_push(_list, ["sta_zp",  0x01,             _id]);
	    array_push(_list, ["lda_lab_lo", _lbl_handler,  _id]);
	    array_push(_list, ["sta_abs",    0xFFFE,        _id]);
	    array_push(_list, ["lda_lab_hi", _lbl_handler,  _id]);
	    array_push(_list, ["sta_abs",    0xFFFF,        _id]);
	    // NOTE: $01 intentionally NOT restored — Kernal must stay banked out
	    // so the CPU reads $FFFE/$FFFF from RAM (our patched vector), not ROM.
	    // The handler uses RTI, not JMP $EA31, so no Kernal dependency.
    } else {
        show_debug_message("IRQ_HANDLER vector write: _lbl_handler=" + _lbl_handler);
        array_push(_list, ["lda_lab_lo", _lbl_handler,  _id]);
        array_push(_list, ["sta_abs",    0x0314,        _id]);
        array_push(_list, ["lda_lab_hi", _lbl_handler,  _id]);
        array_push(_list, ["sta_abs",    0x0315,        _id]);
    }

    // Pre-patch JSR with first slot target so first IRQ fires correctly
    array_push(_list, ["lda_lab_lo", _first_cl,          _id]);
    array_push(_list, ["sta_lab",    _lbl_patch + "_lo", _id]);
    array_push(_list, ["lda_lab_hi", _first_cl,          _id]);
    array_push(_list, ["sta_lab",    _lbl_patch + "_hi", _id]);

    array_push(_list, ["cli",     0,    _id]);
    array_push(_list, ["rts",     0,    _id]);

    // ════════════════════════════════════════════════════════
    // TABLES
    // ════════════════════════════════════════════════════════

    // IRQ index variable (1 byte)
    array_push(_list, ["label",   _lbl_index]);
    array_push(_list, ["byte",    0x00,        _id]);

    // Raster table — unused slots mirror last valid raster
    array_push(_list, ["label",   _lbl_raster]);
    var _last_raster = _first_raster;
 for (var _ti = 0; _ti < 16; _ti++) {
        if (_ti < _irq_count && array_length(_irq_nodes[_ti].instructions[0]) > 1 && is_real(_irq_nodes[_ti].instructions[0][1])) {
            _last_raster = clamp(real(_irq_nodes[_ti].instructions[0][1]), 0, 255);
        }
        array_push(_list, ["byte", _last_raster, _id]);
    }

    // Target lo table — unused slots mirror last valid target
    show_debug_message("IRQ_HANDLER tables: first_cl=" + _first_cl
        + " irq_count=" + string(_irq_count));
    for (var _dbg = 0; _dbg < _irq_count; _dbg++) {
        var _dn = _irq_nodes[_dbg];
        var _dc = (array_length(_dn.instructions[0]) > 5 && string(_dn.instructions[0][5]) != "")
                ? string(_dn.instructions[0][5]) : ("irq" + string(real(_dn)) + "_handler");
        show_debug_message("  slot " + string(_dbg) + " -> " + _dc);
    }
array_push(_list, ["label",   _lbl_tgt_lo]);
    var _last_cl = _first_cl;
    for (var _ti = 0; _ti < 16; _ti++) {
        if (_ti < _irq_count) {
            var _irq_n = _irq_nodes[_ti];
            _last_cl   = (array_length(_irq_n.instructions[0]) > 5 && string(_irq_n.instructions[0][5]) != "")
                       ? string(_irq_n.instructions[0][5])
                       : ("irq" + string(real(_irq_n)) + "_handler");
        }
        array_push(_list, ["byte_lab_lo", _last_cl, _id]);
    }

    // Target hi table — unused slots mirror last valid target
array_push(_list, ["label",   _lbl_tgt_hi]);
    _last_cl = _first_cl;
    for (var _ti = 0; _ti < 16; _ti++) {
        if (_ti < _irq_count) {
            var _irq_n = _irq_nodes[_ti];
            _last_cl   = (array_length(_irq_n.instructions[0]) > 5 && string(_irq_n.instructions[0][5]) != "")
                       ? string(_irq_n.instructions[0][5])
                       : ("irq" + string(real(_irq_n)) + "_handler");
        }
        array_push(_list, ["byte_lab_hi", _last_cl, _id]);
    }

    // ── Spine resumes ─────────────────────────────────────────
    array_push(_list, ["label",   _lbl_skip]);

    show_debug_message("MACRO_IRQ_HANDLER: mode=" + ((_mode==0) ? "KERNAL" : "DIRECT")
        + " irq_count=" + string(_irq_count)
        + " has_sid=" + string(_has_sid_h)
        + " first_raster=$" + string_upper(decimal_to_hex(_first_raster))
        + " first_cl=" + _first_cl);

} break;

// prev IRQ:

// --------------------------------------------------------
// MACRO_IRQ
// Emits a raster IRQ handler and init subroutine.
//
// instructions[0] layout:
//   [0] "macro_irq"
//   [1] raster_line  (0-255)
//   [2] play_music   (0/1 - JSR to sid_play_addr if 1)
//   [3] asset_name   (SID asset, only used if play_music=1)
//
// Exposes two JSR targets on the node:
//   irq_handler_label  = entry point wired to $FFFE/$FFFF
//   irq_init_label     = call once from INIT to hook the vector
//
// The user places JSR nodes pointing to these labels on the spine.
// --------------------------------------------------------
case "MACRO_IRQ": {
    var _id = _curr;

    // Collect and sort all MACRO_IRQ nodes by raster line
    var _irq_nodes = [];
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ" && is_connected && org_parent == noone)
            array_push(_irq_nodes, id);
    }
    array_sort(_irq_nodes, function(_a, _b) {
        var _ra = (array_length(_a.instructions[0]) > 1 && is_real(_a.instructions[0][1])) ? real(_a.instructions[0][1]) : 0x60;
        var _rb = (array_length(_b.instructions[0]) > 1 && is_real(_b.instructions[0][1])) ? real(_b.instructions[0][1]) : 0x60;
        return _ra - _rb;
    });

var _irq_count = array_length(_irq_nodes);
    if (_irq_count == 0) break; // no main-spine IRQ nodes found — skip
    if (_irq_count > 16) _irq_count = 16;
    var _my_index  = -1;
    for (var _ii = 0; _ii < _irq_count; _ii++) {
        if (_irq_nodes[_ii] == _id) { _my_index = _ii; break; }
    }
    if (_my_index == -1) break; // this node not in sorted list — skip

    // If MACRO_IRQ_HANDLER is present, suppress all emission — handler owns everything
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ_HANDLER" && is_connected && org_parent == noone)
            { break; } // exits the with, then falls to break below via _has_irq_handler_node flag
    }
    var _has_irq_handler_node = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_IRQ_HANDLER" && is_connected && org_parent == noone)
            { _has_irq_handler_node = true; break; }
    }
    if (_has_irq_handler_node) break;
	
    var _next_node    = _irq_nodes[(_my_index + 1) mod _irq_count];
    var _is_first     = (_my_index == 0);
    var _raster       = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) ? clamp(real(_id.instructions[0][1]), 0, 255) : 0x60;
    var _next_raster  = (array_length(_next_node.instructions[0]) > 1 && is_real(_next_node.instructions[0][1])) ? clamp(real(_next_node.instructions[0][1]), 0, 255) : 0x60;
    var _first_raster = (array_length(_irq_nodes[0].instructions[0]) > 1 && is_real(_irq_nodes[0].instructions[0][1])) ? clamp(real(_irq_nodes[0].instructions[0][1]), 0, 255) : 0x60;
    var _play_music   = (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2])) ? real(_id.instructions[0][2]) : 0;
    var _asset_name   = (array_length(_id.instructions[0]) > 3) ? string(_id.instructions[0][3]) : "";
    var _call_label   = (array_length(_id.instructions[0]) > 5) ? string(_id.instructions[0][5]) : "";
    var _raster_var   = (array_length(_id.instructions[0]) > 7) ? string(_id.instructions[0][7]) : "";
    var _raster_var_addr = 0;
    if (_raster_var != "") {
        if (ds_map_exists(global.named_loc_map, _raster_var))
            _raster_var_addr = ds_map_find_value(global.named_loc_map, _raster_var);
    }

    var _play_addr = 0x1003;
    if (_play_music && instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if ((_a.type == "SID_MUSIC" || _a.type == "SID_SFX") && _a.name == _asset_name) {
                _play_addr = variable_struct_exists(_a.meta, "sid_play_addr") ? _a.meta.sid_play_addr : _a.address + 3;
                break;
            }
        }
    }

    var _p               = "irq" + string(real(_id)) + "_";
    var _next_p          = "irq" + string(real(_next_node)) + "_";
    var _lbl_handler     = _p + "handler";
    var _lbl_init        = _p + "init";
    var _lbl_skip        = _p + "skip";
    var _next_lbl_handler = _next_p + "handler";

    _id.irq_handler_label = _lbl_handler;
    _id.irq_init_label    = _lbl_init;

	// ── Inline: call init, then skip over subroutines ────
    array_push(_list, ["jsr",     _lbl_init,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip,  _id]);

    // ════════════════════════════════════════════════════
    // IRQ HANDLER
    // ════════════════════════════════════════════════════
array_push(_list, ["label",   _lbl_handler]);
    var _irq_has_sid3 = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
            { _irq_has_sid3 = true; break; }
    }
    if (!_irq_has_sid3) {
        array_push(_list, ["pha",     0,           _id]);
        array_push(_list, ["txa",     0,           _id]);
        array_push(_list, ["pha",     0,           _id]);
        array_push(_list, ["tya",     0,           _id]);
        array_push(_list, ["pha",     0,           _id]);
    }
// Ack VIC and CIA
    array_push(_list, ["lda_imm", 0xFF,        _id]);
    array_push(_list, ["sta_abs", 0xD019,      _id]);
    array_push(_list, ["lda_abs", 0xDC0D,      _id]);
    // When called from sid_irq, wait for our specific raster line
    if (_irq_has_sid3) {
        var _rw = _p + "rw";
        array_push(_list, ["lda_imm", _raster,   _id]);
        array_push(_list, ["label",   _rw            ]);
        array_push(_list, ["cmp_abs", 0xD012,    _id]);
        array_push(_list, ["bne",     _rw,       _id]);
    }
// Dynamic raster from var (if set)
    if (_raster_var != "" && _raster_var_addr != 0) {
        array_push(_list, ["lda_abs", _raster_var_addr, _id]);
        array_push(_list, ["sta_abs", 0xD012,           _id]);
    }
    // User payload
    if (_play_music) {
        array_push(_list, ["jsr", real(_play_addr), _id]);
    }
    if (_call_label != "") {
        array_push(_list, ["jsr", _call_label, _id]);
    }
// Daisy-chain to next handler — standalone only, SID mode uses JSR chain
    var _irq_has_sid5 = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
            { _irq_has_sid5 = true; break; }
    }
    if (_irq_count > 1 && !_irq_has_sid5) {
        array_push(_list, ["lda_lab_lo", _next_lbl_handler, _id]);
        array_push(_list, ["sta_abs",    0xFFFE,             _id]);
        array_push(_list, ["lda_lab_hi", _next_lbl_handler, _id]);
        array_push(_list, ["sta_abs",    0xFFFF,             _id]);
        // Use next node's var if it has one, otherwise hardcoded raster
        var _next_raster_var      = (array_length(_next_node.instructions[0]) > 7) ? string(_next_node.instructions[0][7]) : "";
        var _next_raster_var_addr = 0;
        if (_next_raster_var != "" && ds_map_exists(global.named_loc_map, _next_raster_var))
            _next_raster_var_addr = ds_map_find_value(global.named_loc_map, _next_raster_var);
if (_next_raster_var_addr != 0) {
            array_push(_list, ["lda_abs", _next_raster_var_addr, _id]);
            array_push(_list, ["sta_abs", 0xD012,                _id]);
        } else {
            array_push(_list, ["lda_imm", _next_raster,          _id]);
            array_push(_list, ["sta_abs", 0xD012,                _id]);
        }
    } // end daisy-chain block
// Restore and return — RTS if called from sid_irq chain, RTI if standalone
    var _irq_has_sid = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
            { _irq_has_sid = true; break; }
    }
    if (!_irq_has_sid) {
        array_push(_list, ["pla",     0,           _id]);
        array_push(_list, ["tay",     0,           _id]);
        array_push(_list, ["pla",     0,           _id]);
        array_push(_list, ["tax",     0,           _id]);
        array_push(_list, ["pla",     0,           _id]);
        array_push(_list, ["rti",     0,           _id]);
    } else {
        array_push(_list, ["rts",     0,           _id]);
    }

    // ════════════════════════════════════════════════════
    // INIT SUBROUTINE
    // Only first node does the full setup.
    // All nodes are called inline so SEI state from
    // the spine is already in effect — no SEI/CLI here.
    // ════════════════════════════════════════════════════
    array_push(_list, ["label",   _lbl_init]);

    if (_is_first) {
        // Disable CIA timers permanently
        array_push(_list, ["lda_imm", 0x7F,        _id]);
        array_push(_list, ["sta_abs", 0xDC0D,      _id]);
        array_push(_list, ["sta_abs", 0xDD0D,      _id]);
        array_push(_list, ["lda_abs", 0xDC0E,      _id]);
        array_push(_list, ["and_imm", 0xFE,        _id]);
        array_push(_list, ["sta_abs", 0xDC0E,      _id]);
        array_push(_list, ["lda_abs", 0xDC0F,      _id]);
        array_push(_list, ["and_imm", 0xFE,        _id]);
        array_push(_list, ["sta_abs", 0xDC0F,      _id]);
        // Clear pending interrupts
        array_push(_list, ["lda_abs", 0xDC0D,      _id]);
        array_push(_list, ["lda_abs", 0xDD0D,      _id]);
        // VIC raster setup
// VIC raster setup — force known good state
 //       array_push(_list, ["lda_imm", 0x1B,        _id]);
 //       array_push(_list, ["sta_abs", 0xD011,      _id]);
var _first_raster_var      = (array_length(_irq_nodes[0].instructions[0]) > 7) ? string(_irq_nodes[0].instructions[0][7]) : "";
        var _first_raster_var_addr = 0;
        if (_first_raster_var != "" && ds_map_exists(global.named_loc_map, _first_raster_var))
            _first_raster_var_addr = ds_map_find_value(global.named_loc_map, _first_raster_var);
        if (_first_raster_var_addr != 0) {
            array_push(_list, ["lda_abs", _first_raster_var_addr, _id]);
        } else {
            array_push(_list, ["lda_imm", _first_raster,          _id]);
        }
        array_push(_list, ["sta_abs", 0xD012, _id]);
        array_push(_list, ["lda_imm", 0x81,        _id]);
        array_push(_list, ["sta_abs", 0xD01A,      _id]);
        array_push(_list, ["lda_imm", 0xFF,        _id]);
        array_push(_list, ["sta_abs", 0xD019,      _id]);
        // Wire vector
// Only wire hardware vector if no SID present — SID chains to us via sid_irq
        var _irq_has_sid2 = false;
        with (obj_c64_node) {
            if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
                { _irq_has_sid2 = true; break; }
        }
        if (!_irq_has_sid2) {
            array_push(_list, ["lda_imm", 0x35,            _id]);
            array_push(_list, ["sta_zp",  0x01,            _id]);
            array_push(_list, ["lda_lab_lo", _lbl_handler, _id]);
            array_push(_list, ["sta_abs",    0xFFFE,        _id]);
            array_push(_list, ["lda_lab_hi", _lbl_handler, _id]);
            array_push(_list, ["sta_abs",    0xFFFF,        _id]);
            array_push(_list, ["lda_imm", 0x37,            _id]);
            array_push(_list, ["sta_zp",  0x01,            _id]);
        }
    }
    array_push(_list, ["rts",     0,           _id]);

    // ── Spine resumes here ───────────────────────────────
    array_push(_list, ["label",   _lbl_skip]);
// Last IRQ node — standalone only, SID handles CLI itself
    var _irq_has_sid4 = false;
    with (obj_c64_node) {
        if ((node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER") && is_connected && org_parent == noone)
            { _irq_has_sid4 = true; break; }
    }
    if (_my_index == _irq_count - 1 && !_irq_has_sid4) {
        array_push(_list, ["ldx_imm", 0xFF, _id]);
        array_push(_list, ["txs",     0,    _id]);
        array_push(_list, ["cli",     0,    _id]);
    }

    show_debug_message("MACRO_IRQ: raster=$" + string_upper(decimal_to_hex(_raster))
        + " index=" + string(_my_index) + "/" + string(_irq_count)
        + " first_raster=$" + string_upper(decimal_to_hex(_first_raster))
        + " is_first=" + string(_is_first)
        + " handler=" + _lbl_handler);

} break;



case "MACRO_COLLISION": {
    var _id        = _curr;
    var _group_a   = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) ? real(_id.instructions[0][1]) : 0;
    var _type      = (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2])) ? real(_id.instructions[0][2]) : 0;
    var _jmp_label = (array_length(_id.instructions[0]) > 3) ? string(_id.instructions[0][3]) : "";
    var _mode      = (array_length(_id.instructions[0]) > 4 && is_real(_id.instructions[0][4])) ? real(_id.instructions[0][4]) : 0;
    var _group_b   = (array_length(_id.instructions[0]) > 5 && is_real(_id.instructions[0][5])) ? real(_id.instructions[0][5]) : 0;

    var _uid = string(_id.id);
    _uid = string_replace_all(_uid, " ", "_");
    _uid = string_replace_all(_uid, "[", "");
    _uid = string_replace_all(_uid, "]", "");
    var _skip = "L_EXIT_" + _uid;

    show_debug_message("COLLISION: uid=[" + _uid + "] type=" + string(_type) + " mode=" + string(_mode) + " jmp_label=[" + _jmp_label + "] A=" + string(_group_a) + " B=" + string(_group_b));

    // --- 0. Pre-latch $D01E/$D01F once per frame ---
    // Reading $D01E/$D01F clears them, so read each exactly once at the top
    // of the frame into $F0/$F1. Every collision node then tests those copies.
    if (!global.coll_prelatch_done) {
        array_push(_list, ["lda_abs", 0xD01E, _id]);
        array_push(_list, ["sta_zp",  0xF0,   _id]);
        array_push(_list, ["lda_abs", 0xD01F, _id]);
        array_push(_list, ["sta_zp",  0xF1,   _id]);
        global.coll_prelatch_done = true;
    }

    // --- 1. HW Collision Read (from pre-latched ZP copies) ---
    if (_type == 1) {
        // SPR-BG — read from ZP latch
        array_push(_list, ["lda_zp", 0xF1, _id]);
    } else if (_type == 2) {
        // BOTH — OR the two ZP latch copies
        array_push(_list, ["lda_zp", 0xF0, _id]);
        array_push(_list, ["ora_zp", 0xF1, _id]);
    } else {
        // SPR-SPR — read from ZP latch
        array_push(_list, ["lda_zp", 0xF0, _id]);
    }

    // --- 2. Exact-pair test ---
    // Group A is one sprite, Group B is one sprite. A real collision between
    // THIS pair requires BOTH their bits set in the latch. Isolate the two
    // bits, then CMP against the combined mask — only equal when both present.
    // This avoids the false positive where the shared sprite (e.g. sprite 0)
    // lights up every node's mask via a plain AND.
    var _combined = _group_a | _group_b;
    var _lbl_miss = "L_MISS_" + _uid;

    if (_combined != 0 && _combined != 0xFF) {
        array_push(_list, ["and_imm", _combined, _id]);
        array_push(_list, ["cmp_imm", _combined, _id]);
        if (_mode == 0) {
            // JSR IF HIT — branch away unless both bits present
            array_push(_list, ["bne", _lbl_miss, _id]);
        } else {
            // JSR IF MISS — branch away when both bits present (it hit)
            array_push(_list, ["beq", _lbl_miss, _id]);
        }
    } else {
        // No specific pair set — fall back to "any collision" test
        if (_mode == 0) {
            array_push(_list, ["beq", _lbl_miss, _id]);
        } else {
            array_push(_list, ["bne", _lbl_miss, _id]);
        }
    }

    // --- 3. JSR + exit ---
    if (_jmp_label != "" && _jmp_label != "0") {
        array_push(_list, ["jsr_abs", _jmp_label, _id]);
    }
    array_push(_list, ["jmp_abs", _skip, _id]);
    array_push(_list, ["label",   _lbl_miss]);

    // --- 4. Exit ---
    array_push(_list, ["label", _skip]);
} break;
	
case "MACRO_COLL_ADV": {
    var _id           = _curr;
    var _probe_sprite = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1])) ? real(_id.instructions[0][1]) : 0;
    var _probe_dx     = (array_length(_id.instructions[0]) > 2 && is_real(_id.instructions[0][2])) ? real(_id.instructions[0][2]) : 0;
    var _probe_dy     = (array_length(_id.instructions[0]) > 3 && is_real(_id.instructions[0][3])) ? real(_id.instructions[0][3]) : 0;
    var _map_name     = (array_length(_id.instructions[0]) > 4) ? string(_id.instructions[0][4]) : "";
    var _type_var = (array_length(_id.instructions[0]) > 13) ? string(_id.instructions[0][13]) : "";
    var _loc_var  = (array_length(_id.instructions[0]) > 14) ? string(_id.instructions[0][14]) : "";
    var _col_var  = (array_length(_id.instructions[0]) > 15) ? string(_id.instructions[0][15]) : "";
    var _dx_vnm   = (array_length(_id.instructions[0]) > 16) ? string(_id.instructions[0][16]) : "";
    var _dy_vnm   = (array_length(_id.instructions[0]) > 17) ? string(_id.instructions[0][17]) : "";
    // DIRECT: the byte at $0400 + offset IS the type (written by MOVE_BMP_BLOCK
    // WRITE COLL from the source tags) — skip the TILE_TYPES scan. Char-mode
    // nodes (slot absent or 0) keep the scan.
    var _direct   = (array_length(_id.instructions[0]) > 26 && is_real(_id.instructions[0][26])) ? real(_id.instructions[0][26]) : 0;

   
   var _dx_uv    = (_dx_vnm != "" && _dx_vnm != "[clear]") ? 1 : 0;
    var _dy_uv    = (_dy_vnm != "" && _dy_vnm != "[clear]") ? 1 : 0;

    var _dx_var_addr = 0;
    if (_dx_uv == 1) {
        if (ds_map_exists(global.named_loc_map, _dx_vnm)) {
            _dx_var_addr = ds_map_find_value(global.named_loc_map, _dx_vnm);
        }
        if (_dx_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dx_vnm) {
                    _dx_var_addr = pc_address;
                    break;
                }
            }
        }
    }
    var _dy_var_addr = 0;
    if (_dy_uv == 1) {
        if (ds_map_exists(global.named_loc_map, _dy_vnm)) {
            _dy_var_addr = ds_map_find_value(global.named_loc_map, _dy_vnm);
        }
        if (_dy_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _dy_vnm) {
                    _dy_var_addr = pc_address;
                    break;
                }
            }
        }
    }

    // Resolve output var addresses (0 = not set)
    var _type_var_addr = 0;
    if (_type_var != "" && _type_var != "[clear]") {
        if (ds_map_exists(global.named_loc_map, _type_var)) {
            _type_var_addr = ds_map_find_value(global.named_loc_map, _type_var);
        }
        if (_type_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _type_var) {
                    _type_var_addr = pc_address;
                    break;
                }
            }
        }
    }
    var _loc_var_addr = 0;
    if (_loc_var != "" && _loc_var != "[clear]") {
        if (ds_map_exists(global.named_loc_map, _loc_var)) {
            _loc_var_addr = ds_map_find_value(global.named_loc_map, _loc_var);
        }
        if (_loc_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _loc_var) {
                    _loc_var_addr = pc_address;
                    break;
                }
            }
        }
    }
    var _col_var_addr = 0;
    if (_col_var != "" && _col_var != "[clear]") {
        if (ds_map_exists(global.named_loc_map, _col_var)) {
            _col_var_addr = ds_map_find_value(global.named_loc_map, _col_var);
        }
        if (_col_var_addr == 0) {
            with (obj_c64_node) {
                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _col_var) {
                    _col_var_addr = pc_address;
                    break;
                }
            }
        }
    }

    // Collect type labels: T1..T8 at [5..12], T9..T16 at [18..25]
    var _type_labels = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""];
    for (var _ti = 0; _ti < 16; _ti++) {
        var _src_idx = (_ti < 8) ? (5 + _ti) : (18 + (_ti - 8));
        if (array_length(_id.instructions[0]) > _src_idx) {
            _type_labels[_ti] = string(_id.instructions[0][_src_idx]);
        }
    }

    if (_probe_sprite < 0) _probe_sprite = 0;
    if (_probe_sprite > 7) _probe_sprite = 7;

    var _uid = string(_id.id);
    _uid = string_replace_all(_uid, " ", "_");
    _uid = string_replace_all(_uid, "[", "");
    _uid = string_replace_all(_uid, "]", "");
    var _skip    = "L_EXIT_" + _uid;
    var _sub_lbl = "L_SUB_" + _uid;

    var _final_dx = 12 + _probe_dx;
    var _final_dy = 10 + _probe_dy;

    var _lbl_dx = "COLL_" + _uid + "_DX";
    var _lbl_dy = "COLL_" + _uid + "_DY";

    // ── Ensure COLL_ROW_LO/HI exist ──
    // The probe indexes these to turn a screen row into a $0400+row*40 pointer.
    // Normally a MAP_DATA / META_TILESET node emits them "first map wins", but a
    // pure-bitmap game (DIRECT mode, no map node) has nothing to emit them, so
    // the label would resolve to $0000 and the probe would read zero-page junk
    // instead of the collision map. Emit here under the SAME shared guard, so if
    // a map already emitted them this is a no-op, and if not, COLL_ADV supplies
    // them. Jumped over — they're data, not code.
    if (!variable_global_exists("coll_row_luts_emitted") || global.coll_row_luts_emitted == false) {
        var _crl_skip = "L_CRLUT_" + _uid;
        array_push(_list, ["jmp_abs", _crl_skip, _id]);
        array_push(_list, ["label", "COLL_ROW_LO"]);
        var _crl_lo = [0x00,0x28,0x50,0x78,0xA0,0xC8,0xF0,0x18,0x40,0x68,0x90,0xB8,0xE0,0x08,0x30,0x58,0x80,0xA8,0xD0,0xF8,0x20,0x48,0x70,0x98,0xC0];
        for (var _cri = 0; _cri < 25; _cri++) array_push(_list, ["byte", _crl_lo[_cri], _id]);
        array_push(_list, ["label", "COLL_ROW_HI"]);
        var _crl_hi = [0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x05,0x05,0x05,0x05,0x05,0x05,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x07,0x07,0x07,0x07,0x07];
        for (var _cri = 0; _cri < 25; _cri++) array_push(_list, ["byte", _crl_hi[_cri], _id]);
        array_push(_list, ["label", _crl_skip]);
        global.coll_row_luts_emitted = true;
    }

    var _has_any_handler = false;
    for (var _hi = 0; _hi < 16; _hi++) {
        if (_type_labels[_hi] != "") { _has_any_handler = true; break; }
    }

    show_debug_message("COLL_ADV: uid=[" + _uid + "] spr=" + string(_probe_sprite)
        + " dx=" + string(_probe_dx) + " dy=" + string(_probe_dy)
        + " map=[" + _map_name + "] has_handler=" + string(_has_any_handler));

    // DIRECT mode reads $0400 straight and needs no map — only require a handler.
    // SCAN mode still needs a map to look up TILE_TYPES in.
    var _need_map = (_direct == 0);
    if ((_need_map && _map_name == "") || !_has_any_handler) {
        show_debug_message("COLL_ADV: skipping body (no map or no handlers)");
        // Even when skipping, zero the output vars so stale values don't linger
        if (_type_var_addr != 0) {
            array_push(_list, ["lda_imm", 0,             _id]);
            array_push(_list, ["sta_abs", _type_var_addr, _id]);
        }
        if (_loc_var_addr != 0) {
            array_push(_list, ["lda_imm", 0,            _id]);
            array_push(_list, ["sta_abs", _loc_var_addr,     _id]);
            array_push(_list, ["sta_abs", _loc_var_addr + 1, _id]);
        }
        if (_col_var_addr != 0) {
            array_push(_list, ["lda_imm", 0,            _id]);
            array_push(_list, ["sta_abs", _col_var_addr,     _id]);
            array_push(_list, ["sta_abs", _col_var_addr + 1, _id]);
        }
        array_push(_list, ["label", _skip]);
        break;
    }

    var _tbl_label = _map_name + "_TILE_TYPES";

    // Resolve whether _map_name's linked charset is ECM — if so, the runtime
    // probe byte is a virtual screen code (bits 6-7 = BG band, bits 0-5 = real
    // char), but TILE_TYPES keys are always the real 0-63 char index. Mask the
    // probed byte to 0x3F before the SCAN compare so all 4 bands hit the same
    // type entry. DIRECT mode reads a literal collision tag, not a char code,
    // so it's excluded regardless.
    var _coll_chr_ref = noone;
    if (_map_name != "" && instance_exists(obj_asset_manager)) {
        var _coll_am = obj_asset_manager;
        for (var _coll_ai = 0; _coll_ai < ds_list_size(_coll_am.asset_list); _coll_ai++) {
            var _coll_a = ds_list_find_value(_coll_am.asset_list, _coll_ai);
            if ((_coll_a.type == "MAP_DATA" || _coll_a.type == "META_TILESET") && _coll_a.name == _map_name) {
                if (variable_struct_exists(_coll_a.meta, "chr_asset") && _coll_a.meta.chr_asset != "") {
                    var _coll_chr_nm = _coll_a.meta.chr_asset;
                    for (var _coll_ci = 0; _coll_ci < ds_list_size(_coll_am.asset_list); _coll_ci++) {
                        var _coll_ca = ds_list_find_value(_coll_am.asset_list, _coll_ci);
                        if (_coll_ca.type == "CHAR_SET" && _coll_ca.name == _coll_chr_nm) { _coll_chr_ref = _coll_ca; break; }
                    }
                }
                break;
            }
        }
    }
    var _coll_is_ecm = (_coll_chr_ref != noone) && variable_struct_exists(_coll_chr_ref.meta, "mc_mode") && (_coll_chr_ref.meta.mc_mode == 2);

    array_push(_list, ["jsr_abs", _sub_lbl, _id]);
    array_push(_list, ["sta_zp",  0xF2,     _id]);

    // ---- Write TYPE-RESULT var (A still holds matched type, 0 = none) ----
    if (_type_var_addr != 0) {
        array_push(_list, ["sta_abs", _type_var_addr, _id]);
    }

    // ---- Write LOC var (16-bit screen addr in $F3/$F4, 0 if miss) ----
    // On a miss the sub leaves $F3/$F4 = $0000; on a hit it holds the
    // probed char's screen address.
    if (_loc_var_addr != 0) {
        array_push(_list, ["lda_zp",  0xF3,             _id]);
        array_push(_list, ["sta_abs", _loc_var_addr,     _id]);
        array_push(_list, ["lda_zp",  0xF4,             _id]);
        array_push(_list, ["sta_abs", _loc_var_addr + 1, _id]);
    }

    // ---- Write COL var (colour RAM addr = screen addr + $D400, 0 if miss) ----
    // Screen RAM is $0400-based, colour RAM is $D800-based; the difference is
    // $D400. On a miss ($F3/$F4 == $0000) the COL var is left at $0000.
    if (_col_var_addr != 0) {
        var _col_done = "L_COLDN_" + _uid;
        // If LOC is zero (miss), skip the +$D400 and write $0000
        array_push(_list, ["lda_zp",  0xF3,             _id]);
        array_push(_list, ["ora_zp",  0xF4,             _id]); // A = F3 | F4; zero only if both zero
        array_push(_list, ["bne",     _col_done + "_calc", _id]);
        // Miss path: write $0000
        array_push(_list, ["lda_imm", 0,                _id]);
        array_push(_list, ["sta_abs", _col_var_addr,     _id]);
        array_push(_list, ["sta_abs", _col_var_addr + 1, _id]);
        array_push(_list, ["jmp_abs", _col_done,        _id]);
        // Hit path: COL = ($F3/$F4) + $D400
        array_push(_list, ["label",   _col_done + "_calc"]);
        array_push(_list, ["clc",     0,                _id]);
        array_push(_list, ["lda_zp",  0xF3,             _id]);
        array_push(_list, ["adc_imm", 0x00,             _id]); // $D400 low byte = $00
        array_push(_list, ["sta_abs", _col_var_addr,     _id]);
        array_push(_list, ["lda_zp",  0xF4,             _id]);
        array_push(_list, ["adc_imm", 0xD4,             _id]); // $D400 high byte = $D4
        array_push(_list, ["sta_abs", _col_var_addr + 1, _id]);
        array_push(_list, ["label",   _col_done]);
    }

    for (var _ti = 0; _ti < 16; _ti++) {
        var _lbl = _type_labels[_ti];
        if (_lbl == "" || _lbl == "0") continue;
        var _next_lbl = "L_NT" + string(_ti) + "_" + _uid;
        array_push(_list, ["lda_zp",  0xF2,        _id]);
        array_push(_list, ["cmp_imm", (_ti + 1),   _id]);
        array_push(_list, ["bne",     _next_lbl,   _id]);
        array_push(_list, ["jsr_abs", _lbl,        _id]);
        array_push(_list, ["jmp_abs", _skip,       _id]);
        array_push(_list, ["label",   _next_lbl]);
    }
    array_push(_list, ["jmp_abs", _skip, _id]);

    // Probe subroutine entry
    array_push(_list, ["label", _sub_lbl]);

    array_push(_list, ["lda_abs", 0xD001 + _probe_sprite * 2, _id]);
    if (_dy_uv == 1 && _dy_var_addr != 0) {
        // Add centre-baked literal + signed var, then continue into sec/sbc 50
        // _lbl_dy already holds (10 + node stepper dy) baked at compile time
        // The var is a signed runtime offset on top of that same centre
        // Strategy: load baked literal, add signed var via two's complement adc
        var _dy_var_done = "L_DYVD_" + _uid;
        array_push(_list, ["sta_zp",  0xF2,          _id]); // stash sprite Y
        array_push(_list, ["lda_abs", _lbl_dy,       _id]); // centre-baked literal
        array_push(_list, ["clc",     0,             _id]);
        array_push(_list, ["adc_abs", _dy_var_addr,  _id]); // add signed var (two's complement adc handles sign)
        array_push(_list, ["sta_zp",  0xF5,          _id]); // stash baked+var sum
        array_push(_list, ["lda_zp",  0xF2,          _id]); // restore sprite Y
        // Now apply the combined offset: positive or negative via two's complement add
        array_push(_list, ["clc",     0,             _id]);
        array_push(_list, ["adc_zp",  0xF5,          _id]); // sprite_y + (centre + var)
        // A now holds adjusted sprite Y — fall through into sec/sbc 50 as normal
    } else if (_final_dy != 0) {
        if (_final_dy > 0) {
            array_push(_list, ["clc",     0,                  _id]);
            array_push(_list, ["adc_imm", _final_dy & 0xFF,   _id]);
        } else {
            array_push(_list, ["sec",     0,                    _id]);
            array_push(_list, ["sbc_imm", (-_final_dy) & 0xFF,  _id]);
        }
    }
	
    array_push(_list, ["sec",     0,    _id]);
    array_push(_list, ["sbc_imm", 50,   _id]);
    var _y_ok = "L_YOK_" + _uid;
    array_push(_list, ["bcs",     _y_ok, _id]);
    array_push(_list, ["lda_imm", 0,     _id]);
    array_push(_list, ["label",   _y_ok]);

    repeat(3) array_push(_list, ["lsr_a", 0, _id]);
    array_push(_list, ["cmp_imm", 25,    _id]);
    var _y_clp = "L_YCL_" + _uid;
    array_push(_list, ["bcc",     _y_clp, _id]);
    array_push(_list, ["lda_imm", 24,    _id]);
    array_push(_list, ["label",   _y_clp]);
    array_push(_list, ["tax", 0, _id]);

    array_push(_list, ["lda_abx", "COLL_ROW_LO", _id]);
    array_push(_list, ["sta_zp",  0xF0, _id]);
    array_push(_list, ["lda_abx", "COLL_ROW_HI", _id]);
    array_push(_list, ["sta_zp",  0xF1, _id]);

    // X-coordinate with proper 16-bit handling for $D010 9th bit.
    // Step 1: Build full 16-bit X in $F3 (low) / $F4 (high) — start with sprite X.
    // Step 2: Add $D010 9th bit as +256 to the high byte if set.
    // Step 3: Add user DX (treated as 8-bit, sign-extended into high byte if negative).
    // Step 4: Subtract 24 (border offset).
    // Step 5: Divide by 8 (LSR pair across hi:lo).
    // Step 6: Clamp to 0..39.
    var _x_done  = "L_XDN_"  + _uid;
    var _x_clp   = "L_XCL_"  + _uid;
    var _x_hi9   = "L_XH9_"  + _uid;
    var _x_neg   = "L_XNG_"  + _uid;
    var _x_pos   = "L_XPS_"  + _uid;
    var _x_dxdn  = "L_XDD_"  + _uid;

    // Load sprite X low byte into $F3, zero $F4
    array_push(_list, ["lda_abs", 0xD000 + _probe_sprite * 2, _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["lda_imm", 0,    _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);

    // Apply 9th bit from $D010
    array_push(_list, ["lda_abs", 0xD010, _id]);
    array_push(_list, ["and_imm", (1 << _probe_sprite), _id]);
    array_push(_list, ["beq",     _x_hi9, _id]);
    array_push(_list, ["lda_imm", 1,    _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);
    array_push(_list, ["label",   _x_hi9]);

    // Add user DX from runtime RAM at _lbl_dx (signed; treat 0x80..0xFF as negative)
    // Read once, branch on sign bit
    if (_dx_uv == 1 && _dx_var_addr != 0) {
        // Load centre-baked literal, then add the signed var value on top
        var _dx_var_done = "L_DXVD_" + _uid;
        var _dx_var_neg  = "L_DXVN_" + _uid;
        array_push(_list, ["lda_abs", _lbl_dx,      _id]); // centre-baked literal byte
        array_push(_list, ["sta_zp",  0xF5,         _id]); // stash it
        array_push(_list, ["lda_abs", _dx_var_addr, _id]); // load signed var
        array_push(_list, ["bmi",     _dx_var_neg,  _id]);
        // Positive var: add to baked literal
        array_push(_list, ["clc",     0,            _id]);
        array_push(_list, ["adc_zp",  0xF5,         _id]);
        array_push(_list, ["jmp_abs", _dx_var_done, _id]);
        // Negative var: add as two's complement (carry handles sign correctly)
        array_push(_list, ["label",   _dx_var_neg]);
        array_push(_list, ["clc",     0,            _id]);
        array_push(_list, ["adc_zp",  0xF5,         _id]);
        array_push(_list, ["label",   _dx_var_done]);
        // A now holds baked_centre + var_offset; feed into existing sign branch
        array_push(_list, ["bmi",     _x_neg,       _id]);
    } else {
        array_push(_list, ["lda_abs", _lbl_dx, _id]);
        array_push(_list, ["bmi",     _x_neg,  _id]);
    }
    // Positive DX path: just add to F3, propagate carry into F4
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_zp",  0xF3, _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["lda_zp",  0xF4, _id]);
    array_push(_list, ["adc_imm", 0,    _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);
    array_push(_list, ["jmp_abs", _x_dxdn, _id]);
    // Negative DX path: A holds two's-complement negative; sign-extend high byte = $FF
    array_push(_list, ["label",   _x_neg]);
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_zp",  0xF3, _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["lda_zp",  0xF4, _id]);
    array_push(_list, ["adc_imm", 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);
    array_push(_list, ["label",   _x_dxdn]);

    // Subtract 24 (border) from 16-bit value
    array_push(_list, ["sec",     0,    _id]);
    array_push(_list, ["lda_zp",  0xF3, _id]);
    array_push(_list, ["sbc_imm", 24,   _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["lda_zp",  0xF4, _id]);
    array_push(_list, ["sbc_imm", 0,    _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);

    // Divide by 8 — LSR high, ROR low, three times
    repeat(3) {
        array_push(_list, ["lsr_zp", 0xF4, _id]);
        array_push(_list, ["ror_zp", 0xF3, _id]);
    }

    // Clamp to 0..39: if F4 != 0 (column >= 256), it's off-screen right → clamp to 39
    array_push(_list, ["lda_zp",  0xF4, _id]);
    array_push(_list, ["beq",     _x_done, _id]);
    array_push(_list, ["lda_imm", 39,   _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["label",   _x_done]);

    array_push(_list, ["lda_zp",  0xF3, _id]);
    array_push(_list, ["cmp_imm", 40,   _id]);
    array_push(_list, ["bcc",     _x_clp, _id]);
    array_push(_list, ["lda_imm", 39,   _id]);
    array_push(_list, ["label",   _x_clp]);
    array_push(_list, ["tay", 0, _id]);

    // Compute the probed char's screen address = $F0/$F1 + Y, store in $F3/$F4.
    // This is the candidate LOC value; only committed (kept) on a hit.
    array_push(_list, ["tya",     0,    _id]); // A = column (Y)
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["adc_zp",  0xF0, _id]);
    array_push(_list, ["sta_zp",  0xF3, _id]);
    array_push(_list, ["lda_zp",  0xF1, _id]);
    array_push(_list, ["adc_imm", 0,    _id]);
    array_push(_list, ["sta_zp",  0xF4, _id]);

    array_push(_list, ["lda_iny", 0xF0, _id]);
    if (_coll_is_ecm && _direct == 0) {
        array_push(_list, ["and_imm", 0x3F, _id]); // strip BG-band bits — keep real 0-63 char
    }
    array_push(_list, ["sta_zp",  0xF2, _id]);

    if (_direct == 1) {
        // ── DIRECT (bitmap hybrid) ── the byte in $F2 IS the type.
        // Non-zero = hit, zero = miss. $F3/$F4 already holds the screen address
        // (LOC candidate) — same contract as the scan path, so dispatch is
        // identical downstream.
        var _d_hit = "L_DHT_" + _uid;
        array_push(_list, ["lda_zp",  0xF2,   _id]);
        array_push(_list, ["bne",     _d_hit, _id]);
        array_push(_list, ["lda_imm", 0,      _id]);
        array_push(_list, ["sta_zp",  0xF3,   _id]);
        array_push(_list, ["sta_zp",  0xF4,   _id]);
        array_push(_list, ["lda_imm", 0,      _id]);
        array_push(_list, ["rts",     0,      _id]);
        array_push(_list, ["label",   _d_hit      ]);
        array_push(_list, ["lda_zp",  0xF2,   _id]);
        array_push(_list, ["rts",     0,      _id]);
    } else {
        var _scan = "L_SCN_" + _uid;
        var _hit  = "L_HIT_" + _uid;
        var _miss = "L_MSS_" + _uid;
        array_push(_list, ["ldx_imm", 0,    _id]);
        array_push(_list, ["label",   _scan]);
        array_push(_list, ["lda_abx", _tbl_label, _id]);
        array_push(_list, ["cmp_imm", 0xFF, _id]);
        array_push(_list, ["beq",     _miss, _id]);
        array_push(_list, ["cmp_zp",  0xF2, _id]);
        array_push(_list, ["beq",     _hit, _id]);
        array_push(_list, ["inx", 0, _id]);
        array_push(_list, ["inx", 0, _id]);
        array_push(_list, ["jmp_abs", _scan, _id]);

        array_push(_list, ["label",   _hit]);
        // $F3/$F4 already holds the screen address — leave it intact.
        array_push(_list, ["inx", 0, _id]);
        array_push(_list, ["lda_abx", _tbl_label, _id]);
        array_push(_list, ["rts", 0, _id]);

        array_push(_list, ["label",   _miss]);
        // Miss: zero the LOC candidate so LOC var reads $0000.
        array_push(_list, ["lda_imm", 0,    _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["lda_imm", 0,    _id]);
        array_push(_list, ["rts", 0, _id]);
    }

    // ---- Runtime-mutable DX/DY bytes ----
    // Initialised from the node's current stepper values.
    // Gameplay code can write here to change probe offset on the fly.
    array_push(_list, ["label", _lbl_dx]);
    array_push(_list, ["byte",  _final_dx & 0xFF, _id]);
    array_push(_list, ["label", _lbl_dy]);
    array_push(_list, ["byte",  _final_dy & 0xFF, _id]);

    array_push(_list, ["label", _skip]);
} break;

// NEW
case "MACRO_ANIM": {
    var _id    = _curr;
    var _speed = (array_length(_id.instructions[0]) > 1 && is_real(_id.instructions[0][1]))
               ? clamp(real(_id.instructions[0][1]), 1, 255) : 8;
    var _loop  = (array_length(_id.instructions[0]) > 10 && string(_id.instructions[0][10]) == "1");

    if (!variable_instance_exists(_id, "anim_alias") || _id.anim_alias == "")
        _id.anim_alias = "anim" + string(int64(_id));
    var _p = _id.anim_alias + "_";

    // ── Resolve optional DONE VAR target (UV var written 1=done / 0=running) ──
    var _done_var_name = (array_length(_id.instructions[0]) > 35) ? string(_id.instructions[0][35]) : "";
    var _done_var_addr = -1;
   if (_done_var_name != "" && _done_var_name != "[clear]") {
        for (var _nl = 0; _nl < array_length(global.named_loc_meta); _nl++) {
            var _nlm = global.named_loc_meta[_nl];
            if (_nlm.name == _done_var_name) {
                if (variable_struct_exists(_nlm, "addr")) {
                    _done_var_addr = _nlm.addr;
                }
                break;
            }
        }
    }

    // ── Parse slot frame-offset strings ──────────────────────────────
    // instructions[0][2..9] = comma-separated offset strings e.g. "0,1,2,3,2,1"
    var _slot_frames = [];
    for (var _si = 0; _si < 8; _si++) {
        var _fs = (array_length(_id.instructions[0]) > 2 + _si)
                ? string(_id.instructions[0][2 + _si]) : "";
        var _offsets = [];
        if (_fs != "") {
            var _parts = string_split(_fs, ",");
            for (var _pi = 0; _pi < array_length(_parts); _pi++) {
                var _trimmed = string_replace_all(_parts[_pi], " ", "");
                if (_trimmed != "") {
                    var _val = 0;
                    if (string_char_at(_trimmed, 1) == "$") {
                        _val = hex_to_decimal(string_delete(_trimmed, 1, 1));
                    } else {
                        _val = scr_safe_num(_trimmed);
                    }
                    array_push(_offsets, _val);
                }
            }
        }
        array_push(_slot_frames, _offsets);
    }

    // ── Parse 9th bit flags ───────────────────────────────────────────
    var _slot_9bit = array_create(8, false);
    for (var _si = 0; _si < 8; _si++) {
        _slot_9bit[_si] = (array_length(_id.instructions[0]) > 27 + _si && string(_id.instructions[0][27 + _si]) == "1");
    }

    // ── Parse X/Y delta strings ───────────────────────────────────────
    var _slot_xdeltas = [];
    var _slot_ydeltas = [];
    for (var _si = 0; _si < 8; _si++) {
        var _xs = (array_length(_id.instructions[0]) > 11 + _si) ? string(_id.instructions[0][11 + _si]) : "";
        var _ys = (array_length(_id.instructions[0]) > 19 + _si) ? string(_id.instructions[0][19 + _si]) : "";
        var _xarr = [];
        var _yarr = [];
        if (_xs != "") {
            var _xparts = string_split(_xs, ",");
            for (var _pi = 0; _pi < array_length(_xparts); _pi++) {
                var _t = string_replace_all(_xparts[_pi], " ", "");
                if (_t != "") array_push(_xarr, scr_safe_num(_t) & 0xFF);
            }
        }
        if (_ys != "") {
            var _yparts = string_split(_ys, ",");
            for (var _pi = 0; _pi < array_length(_yparts); _pi++) {
                var _t = string_replace_all(_yparts[_pi], " ", "");
                if (_t != "") array_push(_yarr, scr_safe_num(_t) & 0xFF);
            }
        }
        array_push(_slot_xdeltas, _xarr);
        array_push(_slot_ydeltas, _yarr);
    }

    // ── Derive master count from longest of any slot frame/x/y array ─
    var _master_count = 0;
    for (var _si = 0; _si < 8; _si++) {
        if (array_length(_slot_frames[_si])   > _master_count) _master_count = array_length(_slot_frames[_si]);
        if (array_length(_slot_xdeltas[_si])  > _master_count) _master_count = array_length(_slot_xdeltas[_si]);
        if (array_length(_slot_ydeltas[_si])  > _master_count) _master_count = array_length(_slot_ydeltas[_si]);
    }

    // ── Resolve ptr_reg per slot from matching MACRO_SPR ─────────────
    var _slot_ptr     = array_create(8, -1);
    var _slot_ptr_alt = array_create(8, -1); // [ANIM-SCROLL-FIX] alt buffer pointer

    // [ANIM-SCROLL-FIX] Detect MACRO_SCROLL once — it double-buffers $0400/$0C00
    var _anim_has_scroll = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SCROLL" && is_connected) {
            _anim_has_scroll = true;
            break;
        }
    }

    var _anim_org_parent = _id.org_parent;
    with (obj_c64_node) {
        if (node_type == "MACRO_SPR" && is_connected) {
            if (org_parent != _anim_org_parent) continue;
            var _sslot = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
            if (_sslot >= 0 && _sslot < 8) {
                var _sn_asset = string(instructions[0][1]);
                var _bank_addr  = 0x2800;
                var _screen_ram = -1;
                if (instance_exists(obj_asset_manager) && _sn_asset != "") {
                    var _am2 = obj_asset_manager;
                    for (var _ai2 = 0; _ai2 < ds_list_size(_am2.asset_list); _ai2++) {
                        var _a2 = ds_list_find_value(_am2.asset_list, _ai2);
                        if (_a2.type == "SPRITE_SET" && _a2.name == _sn_asset) {
                            _bank_addr = _a2.address;
                            if (variable_struct_exists(_a2.meta, "screen_ram"))
                                _screen_ram = _a2.meta.screen_ram;
                            break;
                        }
                    }
                }
                // [ANIM-MAP-FIX] MACRO_MAP / MACRO_VIC win over MACRO_BMP for
                // screen RAM resolution — the bitmap is only a transient splash,
                // the later mode switch is authoritative. Check map/VIC first so
                // the frame pointer lands in the active pointer table ($07F8),
                // not the bitmap's stale screen RAM.
var _anim_vic_bank = _bank_addr >> 14;
var _anim_map_wins = false;
if (_anim_vic_bank == 0) {
    with (obj_c64_node) {
        if (is_connected && (node_type == "MACRO_VIC" || node_type == "MACRO_MAP")) {
            _anim_map_wins = true;
            break;
        }
    }
}
if (_screen_ram == -1 && _anim_map_wins) {
    _screen_ram = 0x0400;
}
                if (_screen_ram == -1) {
                    with (obj_c64_node) {
                        if (node_type == "MACRO_BMP" && is_connected) {
                            var _ba   = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0x4000;
                            var _bbk  = floor(_ba / 0x4000);
                            var _bscr = _ba + 0x2000;
                            if (_bbk == 2) _bscr = _bbk * 0x4000 + 0x3C00;
                            if (_bbk == 3) _bscr = _bbk * 0x4000 + 0x0400;
                            _screen_ram = _bscr;
                            break;
                        }
                    }
                }
                var _vic_bank  = _bank_addr >> 14;
                var _bank_base = _vic_bank * 0x4000;
                if (_screen_ram == -1) _screen_ram = _bank_base + 0x0400;
                // [ANIM-MAP-FIX] If map mode is active, force bank 0 base so the
                // frame pointer value matches what MACRO_SPR computed ($A0 etc.)
                if (_anim_map_wins) _bank_base = 0x0000;
                _slot_ptr[_sslot] = _screen_ram + 0x03F8 + _sslot;

                // [ANIM-SCROLL-FIX] Resolve alt pointer table for double-buffered scrolling
                if (_anim_has_scroll) {
                    var _scr1_fixed = 0x0400;
                    var _scr2_fixed = 0x0C00;
                    if (_screen_ram == _scr1_fixed) {
                        _slot_ptr_alt[_sslot] = _scr2_fixed + 0x03F8 + _sslot;
                    } else if (_screen_ram == _scr2_fixed) {
                        _slot_ptr_alt[_sslot] = _scr1_fixed + 0x03F8 + _sslot;
                    } else {
                        // Sprite screen_ram doesn't match scroller buffers — force both
                        _slot_ptr[_sslot]     = _scr1_fixed + 0x03F8 + _sslot;
                        _slot_ptr_alt[_sslot] = _scr2_fixed + 0x03F8 + _sslot;
                    }
                }
            }
        }
    }

    // ── Resolve base pointer value from slot 0 MACRO_SPR asset ───────
    // [ANIM-MAP-FIX] Must use the SAME bank base MACRO_SPR used. In map mode
    // MACRO_SPR forces bank 0 (base $0000), so the pointer byte is computed as
    // (asset_addr - 0) / 64. Mirror that here or the frame advance starts from
    // the wrong pointer when the sprite asset lives outside bank 0.
var _anim_vic_bank = -1;
var _anim_base_map_wins = false;
with (obj_c64_node) {
    if (node_type == "MACRO_SPR" && is_connected) {
        var _sslot2 = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
        if (_sslot2 == 0) {
            var _sn2 = string(instructions[0][1]);
            if (instance_exists(obj_asset_manager) && _sn2 != "") {
                var _am3 = obj_asset_manager;
                for (var _ai3 = 0; _ai3 < ds_list_size(_am3.asset_list); _ai3++) {
                    var _a3 = ds_list_find_value(_am3.asset_list, _ai3);
                    if (_a3.type == "SPRITE_SET" && _a3.name == _sn2) {
                        _anim_vic_bank = _a3.address >> 14;
                        break;
                    }
                }
            }
            break;
        }
    }
}
if (_anim_vic_bank == 0) {
    with (obj_c64_node) {
        if (is_connected && (node_type == "MACRO_VIC" || node_type == "MACRO_MAP")) {
            _anim_base_map_wins = true;
            break;
        }
    }
}
var _base_ptr_val = 0xA0;
    with (obj_c64_node) {
        if (node_type == "MACRO_SPR" && is_connected) {
            var _sslot2 = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
            if (_sslot2 == 0) {
                var _sn2 = string(instructions[0][1]);
                if (instance_exists(obj_asset_manager) && _sn2 != "") {
                    var _am3 = obj_asset_manager;
                    for (var _ai3 = 0; _ai3 < ds_list_size(_am3.asset_list); _ai3++) {
                        var _a3 = ds_list_find_value(_am3.asset_list, _ai3);
                        if (_a3.type == "SPRITE_SET" && _a3.name == _sn2) {
                            var _ba3 = _a3.address;
                            if (_anim_base_map_wins) {
                                _base_ptr_val = (_ba3 / 64);
                            } else {
                                var _bk3 = _ba3 >> 14;
                                _base_ptr_val = ((_ba3 - (_bk3 * 0x4000)) / 64);
                            }
                            break;
                        }
                    }
                }
                break;
            }
        }
    }

    show_debug_message("MACRO_ANIM DEBUG: alias=" + _p
        + " slot_ptr[0]=" + string(_slot_ptr[0])
        + " slot_ptr[1]=" + string(_slot_ptr[1])
        + " base_ptr=$" + string_upper(decimal_to_hex(_base_ptr_val)));

    show_debug_message("MACRO_ANIM: alias=" + _p
        + " loop=" + string(_loop) + " master_count=" + string(_master_count)
        + " base_ptr=$" + string_upper(decimal_to_hex(_base_ptr_val))
        + " done_var=" + _done_var_name + " (" + string(_done_var_addr) + ")");

    var _lbl_sub       = _p + "sub";
    var _lbl_skip      = _p + "skip";
    var _lbl_noadvance = _p + "noadv";
    var _lbl_spd       = _p + "spd";
    var _lbl_fidx      = _p + "fidx";
    var _lbl_done_flag = _p + "donef";
    var _lbl_reset     = _p + "reset";

    // ── Inline: JSR sub then JMP over ────────────────────────────────
    array_push(_list, ["jsr",     _lbl_sub,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);

    // ── Subroutine ────────────────────────────────────────────────────
    array_push(_list, ["label", _lbl_sub]);

    // ── One-shot guard: if finished, RTS until reset re-arms it ──────
    if (!_loop) {
        var _lbl_notdone = _p + "ntdn";
        array_push(_list, ["lda_lab", _lbl_done_flag, _id]);
        array_push(_list, ["beq",     _lbl_notdone,   _id]);
        array_push(_list, ["rts",     0,              _id]);
        array_push(_list, ["label",   _lbl_notdone]);
    }

    // If master count is zero there is nothing to do — safe no-op stub
    if (_master_count == 0) {
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _lbl_noadvance]);
        array_push(_list, ["label", _lbl_skip]);
        break;
    }

    // Decrement speed counter
    array_push(_list, ["dec_lab", _lbl_spd, _id]);

    // Springboard: if counter not zero jump to noadvance via JMP
    var _lbl_spring = _p + "spr";
    array_push(_list, ["beq",     _lbl_spring,    _id]);
    array_push(_list, ["jmp_abs", _lbl_noadvance, _id]);

    array_push(_list, ["label",   _lbl_spring]);

    // Reload speed, advance master frame index
    array_push(_list, ["lda_imm", _speed,        _id]);
    array_push(_list, ["sta_lab", _lbl_spd,      _id]);
    // DONE VAR stays 0 while actively advancing
    if (_done_var_addr != -1) {
        array_push(_list, ["lda_imm", 0x00,           _id]);
        array_push(_list, ["sta_abs", _done_var_addr, _id]);
    }
    array_push(_list, ["inc_lab", _lbl_fidx,     _id]);
    array_push(_list, ["lda_lab", _lbl_fidx,     _id]);
    array_push(_list, ["cmp_imm", _master_count, _id]);
    var _lbl_nowrap = _p + "nowrp";
    array_push(_list, ["bcc", _lbl_nowrap, _id]);
    if (_loop) {
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_lab", _lbl_fidx, _id]);
    } else {
        // Overflow guard only — clamp index, done was already latched on the
        // call that landed on the final frame (see post-nowrap check below).
        array_push(_list, ["lda_imm", _master_count - 1, _id]);
        array_push(_list, ["sta_lab", _lbl_fidx,         _id]);
    }
    array_push(_list, ["label", _lbl_nowrap]);

    // ── One-shot done latch: fire the frame we APPLY the last frame ──
    // After clamping, fidx holds the frame about to be applied this call.
    // For non-loop, when that frame == master_count-1, latch done now so
    // the DONE var is true on the same call that shows the final frame.
    if (!_loop) {
        var _lbl_notlast = _p + "ntlst";
        array_push(_list, ["lda_lab", _lbl_fidx,         _id]);
        array_push(_list, ["cmp_imm", _master_count - 1, _id]);
        array_push(_list, ["bne",     _lbl_notlast,      _id]);
        array_push(_list, ["lda_imm", 0x01,              _id]);
        array_push(_list, ["sta_lab", _lbl_done_flag,    _id]);
        if (_done_var_addr != -1) {
            array_push(_list, ["lda_imm", 0x01,           _id]);
            array_push(_list, ["sta_abs", _done_var_addr, _id]);
        }
        array_push(_list, ["label", _lbl_notlast]);
    }

// ── Per-slot code emission (INDEXED) ──────────────────────────────
    // fidx holds the master frame index (0.._master_count-1). It is loaded
    // into X once and reused across all three axes; nothing below clobbers X.
    // Each axis reads its own pre-expanded table (see inline-data block) with
    // lda_abx <label>,X. Per-frame CMP/BNE ladders are gone; cost is now fixed
    // per slot regardless of frame count.
    var _x_loaded = false;
    for (var _si = 0; _si < 8; _si++) {
        var _offsets = _slot_frames[_si];
        var _xdeltas = _slot_xdeltas[_si];
        var _ydeltas = _slot_ydeltas[_si];

        var _has_frames  = (array_length(_offsets) > 0);
        var _has_xdeltas = (array_length(_xdeltas) > 0);
        var _has_ydeltas = (array_length(_ydeltas) > 0);
        var _has_spr_ptr = (_slot_ptr[_si] != -1);

        // Skip slot entirely if nothing to do
        if (!_has_frames && !_has_xdeltas && !_has_ydeltas) {
            continue;
        }

        // Load fidx into X exactly once, on the first slot that needs it
        if (!_x_loaded) {
            array_push(_list, ["ldx_lab", _lbl_fidx, _id]);
            _x_loaded = true;
        }

        // ── Frame dispatch — indexed table read ───────────────────────
        if (_has_frames && _has_spr_ptr) {
            array_push(_list, ["lda_abx", _p + "ftbl" + string(_si), _id]);
            array_push(_list, ["clc",     0,                         _id]);
            array_push(_list, ["adc_imm", _base_ptr_val,             _id]);
            array_push(_list, ["sta_abs", _slot_ptr[_si],            _id]);
            // [ANIM-SCROLL-FIX] Mirror to alt buffer pointer table
            if (_slot_ptr_alt[_si] != -1) {
                array_push(_list, ["sta_abs", _slot_ptr_alt[_si], _id]);
            }
        }

        // ── X delta — indexed, runtime 9th-bit (mixed-direction safe) ─
        // The delta sign and the add's carry-out together decide the MSB
        // toggle, so we branch on sign first then on carry. This is correct
        // for sequences that change direction mid-cycle (e.g. -2,-4,-8,8,4,2).
        if (_has_xdeltas) {
            var _hw_x = 0xD000 + _si * 2;
            array_push(_list, ["lda_abx", _p + "xtbl" + string(_si), _id]);
            if (_slot_9bit[_si]) {
                var _lbl_xneg = _p + "x9neg" + string(_si);
                var _lbl_xtog = _p + "x9tog" + string(_si);
                var _lbl_xend = _p + "x9end" + string(_si);
                array_push(_list, ["bmi",     _lbl_xneg, _id]); // delta < 0 → left move
                // Positive (right move): carry SET after add means wrap → toggle
                array_push(_list, ["clc",     0,         _id]);
                array_push(_list, ["adc_abs", _hw_x,     _id]);
                array_push(_list, ["sta_abs", _hw_x,     _id]);
                array_push(_list, ["bcc",     _lbl_xend, _id]); // no wrap → skip toggle
                array_push(_list, ["jmp_abs", _lbl_xtog, _id]);
                // Negative (left move): carry CLEAR after add means wrap → toggle
                array_push(_list, ["label",   _lbl_xneg]);
                array_push(_list, ["clc",     0,         _id]);
                array_push(_list, ["adc_abs", _hw_x,     _id]);
                array_push(_list, ["sta_abs", _hw_x,     _id]);
                array_push(_list, ["bcs",     _lbl_xend, _id]); // no wrap → skip toggle
                // Shared MSB toggle
                array_push(_list, ["label",   _lbl_xtog]);
                array_push(_list, ["lda_abs", 0xD010,            _id]);
                array_push(_list, ["eor_imm", (1 << _si) & 0xFF, _id]);
                array_push(_list, ["sta_abs", 0xD010,            _id]);
                array_push(_list, ["label",   _lbl_xend]);
            } else {
                array_push(_list, ["clc",     0,     _id]);
                array_push(_list, ["adc_abs", _hw_x, _id]);
                array_push(_list, ["sta_abs", _hw_x, _id]);
            }
        }

        // ── Y delta — indexed table read ──────────────────────────────
        if (_has_ydeltas) {
            var _hw_y = 0xD001 + _si * 2;
            array_push(_list, ["lda_abx", _p + "ytbl" + string(_si), _id]);
            array_push(_list, ["clc",     0,     _id]);
            array_push(_list, ["adc_abs", _hw_y, _id]);
            array_push(_list, ["sta_abs", _hw_y, _id]);
        }
    }

    // ── Noadvance / RTS ───────────────────────────────────────────────
    array_push(_list, ["label", _lbl_noadvance]);
    array_push(_list, ["rts",   0, _id]);

    // ── Inline data ───────────────────────────────────────────────────
    array_push(_list, ["label", _lbl_spd]);
    array_push(_list, ["byte",  0x01, _id]); // Start at 1 so it ticks immediately
    array_push(_list, ["label", _lbl_fidx]);
    array_push(_list, ["byte",  0xFF, _id]); // Start at 0xFF so first INC wraps to 0
    array_push(_list, ["label", _lbl_done_flag]);
    array_push(_list, ["byte",  0x00, _id]); // 0 = armed, 1 = one-shot finished

// ── Per-axis tables, pre-expanded to _master_count bytes ──────────
    // Each table is one contiguous run indexed by the master frame in X.
    // Per-entry index uses the slot's OWN array length with the same rule
    // the old ladder applied per frame: loop -> (fi % len), one-shot ->
    // min(fi, len-1). This preserves identical behaviour when a slot's
    // frame/X/Y arrays differ in length. At <16 frames the padding cost is
    // a handful of bytes per table; the code-side saving dwarfs it.

    // Frame offset tables — only emit if ptr is known
    for (var _si = 0; _si < 8; _si++) {
        var _offsets = _slot_frames[_si];
        var _len_off = array_length(_offsets);
        if (_len_off == 0) {
            continue;
        }
        if (_slot_ptr[_si] == -1) {
            continue;
        }
        array_push(_list, ["label", _p + "ftbl" + string(_si)]);
        for (var _fi = 0; _fi < _master_count; _fi++) {
            var _di = 0;
            if (_loop) {
                _di = _fi % _len_off;
            } else {
                _di = min(_fi, _len_off - 1);
            }
            array_push(_list, ["byte", _offsets[_di] & 0xFF, _id]);
        }
    }

    // X delta tables — emit freely, no ptr check needed
    for (var _si = 0; _si < 8; _si++) {
        var _xdeltas = _slot_xdeltas[_si];
        var _len_x   = array_length(_xdeltas);
        if (_len_x == 0) {
            continue;
        }
        array_push(_list, ["label", _p + "xtbl" + string(_si)]);
        for (var _fi = 0; _fi < _master_count; _fi++) {
            var _di = 0;
            if (_loop) {
                _di = _fi % _len_x;
            } else {
                _di = min(_fi, _len_x - 1);
            }
            array_push(_list, ["byte", _xdeltas[_di] & 0xFF, _id]);
        }
    }

    // Y delta tables — emit freely, no ptr check needed
    for (var _si = 0; _si < 8; _si++) {
        var _ydeltas = _slot_ydeltas[_si];
        var _len_y   = array_length(_ydeltas);
        if (_len_y == 0) {
            continue;
        }
        array_push(_list, ["label", _p + "ytbl" + string(_si)]);
        for (var _fi = 0; _fi < _master_count; _fi++) {
            var _di = 0;
            if (_loop) {
                _di = _fi % _len_y;
            } else {
                _di = min(_fi, _len_y - 1);
            }
            array_push(_list, ["byte", _ydeltas[_di] & 0xFF, _id]);
        }
    }

    // ── Reset entry: JSR here to re-arm the one-shot ──────────────────
    // Restores fidx=$FF, speed counter=$01, clears done flag + DONE VAR, then RTS.
    if (!_loop) {
        array_push(_list, ["jmp_abs", _lbl_skip,      _id]); // step over reset routine in normal flow
        array_push(_list, ["label",   _lbl_reset]);
        array_push(_list, ["lda_imm", 0xFF,           _id]);
        array_push(_list, ["sta_lab", _lbl_fidx,      _id]);
        array_push(_list, ["lda_imm", 0x01,           _id]);
        array_push(_list, ["sta_lab", _lbl_spd,       _id]);
        array_push(_list, ["lda_imm", 0x00,           _id]);
        array_push(_list, ["sta_lab", _lbl_done_flag, _id]);
        // Clear user DONE VAR on re-arm
        if (_done_var_addr != -1) {
            array_push(_list, ["lda_imm", 0x00,           _id]);
            array_push(_list, ["sta_abs", _done_var_addr, _id]);
        }
        array_push(_list, ["rts",     0,              _id]);
    }

    // ── Spine resumes ─────────────────────────────────────────────────
    array_push(_list, ["label", _lbl_skip]);

} break;



// ════════════════════════════════════════════════════════════════════
	// MACRO_VECTOR_PAGE — flip a multi-page VECTOR_BITMAP to a chosen page.
	// instructions[0]: ["macro_vector_page", asset_name, page_index]
	// Depends on a MACRO_VECTOR_BMP (setup) node earlier on the spine having
	// emitted the shared runtime + this asset's page streams. Does NOT touch
	// VIC config ($D011/$D016/$D018/$DD00) — setup owns that. Per flip it:
	//   jsr vbmp_clear            (wipe the $4000 bitmap)
	//   fill screen RAM + colour RAM + $D021 from THIS page's 4 colours
	//   point $FB/$FC at vbmp_<asset>_p<N>_stream ; jsr vbmp_render
	// ════════════════════════════════════════════════════════════════════
case "MACRO_VECTOR_PAGE": {
		var _id         = _curr;
		var _asset_name = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";

		// ── Normalise instruction layout to house convention ──
		// ["macro_vector_page", asset, use_var_flag, page_or_varname]
		// Legacy saves stored the literal page index in slot 2 with no slot 3.
		// Detect (slot 3 absent) and migrate: slot 3 = old page, slot 2 = 0.
		while (array_length(_curr.instructions[0]) < 4) {
			array_push(_curr.instructions[0], 0);
		}
		if (!is_real(_curr.instructions[0][2])) _curr.instructions[0][2] = 0;
		var _use_var  = real(_curr.instructions[0][2]);
		var _var_name = is_string(_curr.instructions[0][3]) ? _curr.instructions[0][3] : "";

		// ══════════════════════════════════════════════════════════════
		// VAR-DRIVEN branch — a UV variable holds the page index. The
		// per-asset LUTs + dispatch routine (vbmp_<key>_dispatch) are
		// emitted by the SETUP node (MACRO_VECTOR_BMP) when it detects a
		// var-driven PAGE node targeting its asset. Here we only resolve
		// the var and call the dispatcher: ldx_abs var, jsr dispatch.
		// ══════════════════════════════════════════════════════════════
		if (_use_var == 1) {
			var _vp_var_addr = -1;
			if (_var_name != "" && ds_map_exists(global.named_loc_map, _var_name)) {
				_vp_var_addr = ds_map_find_value(global.named_loc_map, _var_name);
			}
			if (_vp_var_addr < 0) {
				show_debug_message("MACRO_VECTOR_PAGE(VAR): page var '" + _var_name + "' not resolved — skipping");
				break;
			}
			if (_asset_name == "") {
				show_debug_message("MACRO_VECTOR_PAGE(VAR): no asset set — skipping");
				break;
			}
			var _vp_key = scr_vbmp_label_key(_asset_name);
			// X = page index from the game var; dispatcher does the rest
			// (stash X in $D3, clear, LUT fills, $D021, stream ptr, render).
			array_push(_list, ["ldx_abs", _vp_var_addr,               _id]);
			array_push(_list, ["jsr",     "vbmp_" + _vp_key + "_dispatch", _id]);
			break;
		}

		// ── LIT branch — page index now lives in slot 3 ──
		var _page_idx   = (is_real(_curr.instructions[0][3])) ? real(_curr.instructions[0][3]) : 0;

		// ── Resolve the VECTOR_BITMAP asset ──
		var _vb = noone;
		if (_asset_name != "" && instance_exists(obj_asset_manager)) {
			var _am = obj_asset_manager;
			for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
				var _a = ds_list_find_value(_am.asset_list, _ai);
				if (_a.type == "VECTOR_BITMAP" && _a.name == _asset_name) { _vb = _a; break; }
			}
		}
		if (_vb == noone) {
			show_debug_message("MACRO_VECTOR_PAGE: asset '" + _asset_name + "' not found — skipping");
			break;
		}

		var _vm       = _vb.meta;
		var _bmp_base = _vb.address;

		// Unique label prefix per PAGE-node instance for its scrfill/colfill loops.
		var _pfx_pg   = "vpage_" + string(real(_id)) + "_";

		// Resolve the chosen page struct + its 4 colours.
		var _pages = (variable_struct_exists(_vm, "pages") && is_array(_vm.pages)) ? _vm.pages : [];
		if (_page_idx < 0 || _page_idx >= array_length(_pages)) {
			show_debug_message("MACRO_VECTOR_PAGE: asset '" + _asset_name + "' has no page " + string(_page_idx) + " (pages=" + string(array_length(_pages)) + ") — skipping");
			break;
		}
		var _pg      = _pages[_page_idx];
		var _pg_bg   = variable_struct_exists(_pg, "bg")   ? (real(_pg.bg)   & 0x0F) : 0;
		var _pg_col1 = variable_struct_exists(_pg, "col1") ? (real(_pg.col1) & 0x0F) : 1;
		var _pg_col2 = variable_struct_exists(_pg, "col2") ? (real(_pg.col2) & 0x0F) : 2;
		var _pg_col3 = variable_struct_exists(_pg, "col3") ? (real(_pg.col3) & 0x0F) : 3;

		// Screen RAM base: same rule as the setup node ($6000 in bank 1 unless
		// meta overrides). Both nodes must agree so the flip paints the right RAM.
		var _scr_ram = variable_struct_exists(_vm, "screen_ram") ? real(_vm.screen_ram) : 0x6000;
		var _scr_val = ((_pg_col1 << 4) | _pg_col2) & 0xFF;

		// Asset-keyed stream label for the chosen page (matches setup emission).
		var _asset_key = scr_vbmp_label_key(_asset_name);
		var _pg_label  = _asset_key + "_p" + string(_page_idx) + "_stream";

		array_push(_list, ["sei", 0, _id]);

		// bmp_base into $F9/$FA (vbmp_clear + vbmp_plot read it).
		array_push(_list, ["lda_imm", _bmp_base & 0xFF,        _id]);
		array_push(_list, ["sta_zp",  0xF9,                    _id]);
		array_push(_list, ["lda_imm", (_bmp_base >> 8) & 0xFF, _id]);
		array_push(_list, ["sta_zp",  0xFA,                    _id]);

		// Wipe the bitmap.
		array_push(_list, ["jsr", "vbmp_clear", _id]);

		// Fill screen RAM ($scr..$scr+03E7) with (col1<<4)|col2 → 1000 bytes.
		array_push(_list, ["lda_imm", _scr_val,               _id]);
		array_push(_list, ["ldx_imm", 0x00,                   _id]);
		array_push(_list, ["label",   _pfx_pg + "scrfill"]);
		array_push(_list, ["sta_abx", _scr_ram,               _id]);
		array_push(_list, ["sta_abx", _scr_ram + 0x100,       _id]);
		array_push(_list, ["sta_abx", _scr_ram + 0x200,       _id]);
		array_push(_list, ["sta_abx", _scr_ram + 0x2E8,       _id]);
		array_push(_list, ["inx",     0,                      _id]);
		array_push(_list, ["bne",     _pfx_pg + "scrfill",    _id]);

		// Fill colour RAM ($D800..$DBE7) with col3 → 1000 bytes.
		array_push(_list, ["lda_imm", _pg_col3,               _id]);
		array_push(_list, ["ldx_imm", 0x00,                   _id]);
		array_push(_list, ["label",   _pfx_pg + "colfill"]);
		array_push(_list, ["sta_abx", 0xD800,                 _id]);
		array_push(_list, ["sta_abx", 0xD900,                 _id]);
		array_push(_list, ["sta_abx", 0xDA00,                 _id]);
		array_push(_list, ["sta_abx", 0xDAE8,                 _id]);
		array_push(_list, ["inx",     0,                      _id]);
		array_push(_list, ["bne",     _pfx_pg + "colfill",    _id]);

		// $D021 = this page's bg.
		array_push(_list, ["lda_imm", _pg_bg,                 _id]);
		array_push(_list, ["sta_abs", 0xD021,                 _id]);

		// Screen-RAM base into $DB/$DC (runtime recolour SRAM opcode reads it).
		array_push(_list, ["lda_imm", _scr_ram & 0xFF,        _id]);
		array_push(_list, ["sta_zp",  0xDB,                   _id]);
		array_push(_list, ["lda_imm", (_scr_ram >> 8) & 0xFF, _id]);
		array_push(_list, ["sta_zp",  0xDC,                   _id]);

		// Point stream ptr at the chosen page + render.
		array_push(_list, ["lda_lab_lo", _pg_label, _id]);
		array_push(_list, ["sta_zp",     0xFB,      _id]);
		array_push(_list, ["lda_lab_hi", _pg_label, _id]);
		array_push(_list, ["sta_zp",     0xFC,      _id]);
		array_push(_list, ["jsr",        "vbmp_render", _id]);

		array_push(_list, ["cli", 0, _id]);
	} break;
	
// --------------------------------------------------------
// MACRO_VECTOR_BMP  (STAGE 1: interpreter + MC plot, PLOT/SETCOL/END only)
// instructions[0]: ["macro_vector_bmp", asset_name, fill_stack_addr, render_now]
//
// Emits (in order):
//   1. Shared runtime (vbmp_render interpreter + vbmp_plot + BMPCHARROW
//      tables), ONCE per build under global.vbmp_runtime_emitted, tagged _id
//      so Pass 1.5 sizes it onto this node. Jumped over with jmp_abs.
//   2. Per-node: load stream ptr into $FB/$FC, optional JSR vbmp_render.
//   3. Off-spine (org -2 / org -3, _id = noone): this asset's command stream.
//
// ZP: $FB/$FC stream ptr | $F2/$F3 plot byte ptr | $F4 pair scratch
//     $F5/$F6 plot x lo/hi | $F7 plot y | $F8 active selector (0-3)
// --------------------------------------------------------
case "MACRO_VECTOR_BMP": {
    var _id         = _curr;
    var _asset_name = (array_length(_curr.instructions[0]) > 1) ? string(_curr.instructions[0][1]) : "";
    var _fill_stack = (array_length(_curr.instructions[0]) > 2 && is_real(_curr.instructions[0][2])) ? real(_curr.instructions[0][2]) : 0;
    var _render_now = (array_length(_curr.instructions[0]) > 3 && is_real(_curr.instructions[0][3])) ? real(_curr.instructions[0][3]) : 1;

    // ── Resolve the VECTOR_BITMAP asset ──
    var _vb        = noone;
    if (_asset_name != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "VECTOR_BITMAP" && _a.name == _asset_name) { _vb = _a; break; }
        }
    }
    if (_vb == noone) {
        show_debug_message("MACRO_VECTOR_BMP: asset '" + _asset_name + "' not found — skipping");
        break;
    }

    var _vm        = _vb.meta;
    var _bmp_base  = _vb.address;
    var _vb_mode   = (variable_struct_exists(_vm, "mode")) ? _vm.mode : 1; // 1 = MC
    var _commands  = (variable_struct_exists(_vm, "commands") && is_array(_vm.commands)) ? _vm.commands : [];

    // ── PRE-SCAN: does any var-driven MACRO_VECTOR_PAGE node target THIS asset? ──
    // Only then do we emit this asset's per-page LUTs + dispatch routine.
    // Collect matches into an array first (reading enclosing locals through
    // other. inside a with() throws), then test the array outside the with().
    var _vp_scan = [];
    with (obj_c64_node) {
        if (node_type == "MACRO_VECTOR_PAGE") {
            // Normalise-safe reads: slot 2 = use_var flag, slot 1 = asset,
            // slot 3 = var name (only meaningful when the flag is 1).
            var _sc_uv = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
            if (_sc_uv == 1) {
                var _sc_asset = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
                array_push(_vp_scan, _sc_asset);
            }
        }
    }
    var _vp_needs_dispatch = false;
    for (var _vpi = 0; _vpi < array_length(_vp_scan); _vpi++) {
        if (_vp_scan[_vpi] == _asset_name) { _vp_needs_dispatch = true; break; }
    }

    // Fill-stack address: node override wins, else default $8000.
    // Stream is derived as base + $0800 (see _stream_addr below).
    if (_fill_stack == 0) {
        _fill_stack = 0x8000;
    }

    // Unique label prefix per node instance for this node's stream
    var _pfx        = "vbmp_" + string(real(_id)) + "_";
    var _lbl_stream = _pfx + "stream";

    // ════════════════════════════════════════════════════════════════
    // SHARED RUNTIME — emitted once per build, jumped over inline.
    // Tagged _id so Pass 1.5 (scr_c64_do_update_addresses) counts it.
    // ════════════════════════════════════════════════════════════════
    if (!variable_global_exists("vbmp_runtime_emitted") || global.vbmp_runtime_emitted == false) {
        global.vbmp_runtime_emitted = true;

        array_push(_list, ["jmp_abs", "vbmp_rt_skip", _id]);

        // ── BMPCHARROW_LO/HI: base byte offset of each of the 25 char rows ──
        // row N starts at bitmap byte N*320. Stored as base+offset is awkward
        // (base varies per asset), so we store the PURE offset (N*320) and add
        // the per-asset base at render entry. 25 entries.
        array_push(_list, ["label", "BMPCHARROW_LO"]);
        for (var _r = 0; _r < 25; _r++) array_push(_list, ["byte", (_r * 320) & 0xFF, _id]);
        array_push(_list, ["label", "BMPCHARROW_HI"]);
        for (var _r = 0; _r < 25; _r++) array_push(_list, ["byte", ((_r * 320) >> 8) & 0xFF, _id]);

        // ── VBMP_CIRCLE_Y: normalized quarter-arc, 97 entries (x = 0..96). ──
        // y = round( sqrt(1 - (x/96)^2) * 255 ). Scaled at runtime by (val*ry)>>8.
        array_push(_list, ["label", "VBMP_CIRCLE_Y"]);
        for (var _cx = 0; _cx <= 96; _cx++) {
            var _norm = sqrt(1 - (_cx / 96) * (_cx / 96));
            var _yv   = round(_norm * 255);
            if (_yv > 255) _yv = 255;
            if (_yv < 0)   _yv = 0;
            array_push(_list, ["byte", _yv, _id]);
        }

        // (Reciprocal tables removed — vbmp_ellipse now uses px*96/rx directly.)

        // ── vbmp_plot ──
        // Entry: $F5/$F6 = x (0..319), $F7 = y (0..199), $F8 = selector (0..3).
        // Computes byte addr = bmp_base + BMPCHARROW[y>>3] + (y&7) + ((x>>3)<<3)
        // into $F2/$F3, then writes the 2-bit selector into pair (x>>1)&3.
        // bmp_base is held in $F9/$FA (set once at render entry).
        // Clobbers A, X, Y. Preserves $FB/$FC (stream ptr) untouched.
        array_push(_list, ["label", "vbmp_plot"]);

        // X = y >> 3  (char row index)
        array_push(_list, ["lda_zp",  0xF7, _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["tax",     0,    _id]);

        // $F2/$F3 = bmp_base + BMPCHARROW[X]
        array_push(_list, ["clc",     0,             _id]);
        array_push(_list, ["lda_zp",  0xF9,          _id]); // bmp_base lo
        array_push(_list, ["adc_abx", "BMPCHARROW_LO", _id]);
        array_push(_list, ["sta_zp",  0xF2,          _id]);
        array_push(_list, ["lda_zp",  0xFA,          _id]); // bmp_base hi
        array_push(_list, ["adc_abx", "BMPCHARROW_HI", _id]);
        array_push(_list, ["sta_zp",  0xF3,          _id]);

        // += (y & 7)
        array_push(_list, ["lda_zp",  0xF7, _id]);
        array_push(_list, ["and_imm", 0x07, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xF2, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xF3, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);

        // += ((x>>3) << 3)  — i.e. (x & ~7) with the 9th bit folded in.
        // x is 0..319 so x>>3 is 0..39; (x>>3)<<3 is 0..312, fits with carry.
        // Compute col = x>>3 into A (16-bit x in $F5/$F6), then col*8.
        // col = (x >> 3): shift the 16-bit value right 3 times.
        array_push(_list, ["lda_zp",  0xF6, _id]); // x hi
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]); // stash hi>>1 (only bit 0 of hi matters: x max 319 -> hi max 1)
        array_push(_list, ["lda_zp",  0xF5, _id]); // x lo
        array_push(_list, ["ror_a",   0,    _id]); // (x>>1) lo, carry from hi
        array_push(_list, ["lsr_a",   0,    _id]); // >>2 total
        array_push(_list, ["lsr_a",   0,    _id]); // >>3 total  -> col 0..39 (hi contributes via +256>>3=32)
        // add hi contribution: if x>=256, col += 32. $F4 held (hi>>1); for x<=319 hi is 0 or 1.
        // hi=1 -> col bit: 256>>3 = 32. Add 32 when original hi bit0 was set.
        array_push(_list, ["sta_zp",  0xF4, _id]); // $F4 = partial col (low part)
        array_push(_list, ["lda_zp",  0xF6, _id]);
        array_push(_list, ["and_imm", 0x01, _id]); // original hi bit
        array_push(_list, ["beq",     "vbmp_plot_nocolhi", _id]);
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 32,   _id]); // 256>>3
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["label",   "vbmp_plot_nocolhi"]);
        // col now in $F4 (0..39). col*8 = col<<3.
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["asl_a",   0,    _id]); // *2
        array_push(_list, ["asl_a",   0,    _id]); // *4
        array_push(_list, ["asl_a",   0,    _id]); // *8 (col<=39 -> max 312, overflows 1 byte: need 16-bit)
        // col*8 can be up to 312, so capture carry into a hi byte.
        array_push(_list, ["sta_zp",  0xF4, _id]); // col*8 lo
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["rol_a",   0,    _id]); // catch carry from last ASL into bit0
        // add col*8 (16-bit: $F4 lo, A hi) to $F2/$F3
        array_push(_list, ["pha",     0,    _id]); // save hi
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["adc_zp",  0xF2, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["pla",     0,    _id]); // hi
        array_push(_list, ["adc_zp",  0xF3, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);

        // ── Now $F2/$F3 = exact bitmap byte. Write the 2-bit selector. ──
        if (_vb_mode == 1) {
            // MC: pair index = (x>>1) & 3, from the LEFT (pair 0 = bits 7-6).
            // shift amount = 6 - pair*2 = (3-pair)*2.
            // Build mask = 0b11 << shift, value = selector << shift.
            // pair = (x>>1)&3
            array_push(_list, ["lda_zp",  0xF5, _id]); // x lo
            array_push(_list, ["lsr_a",   0,    _id]); // x>>1 (bit shifted; bit1.. )
            array_push(_list, ["and_imm", 0x03, _id]); // pair 0..3
            array_push(_list, ["tax",     0,    _id]); // X = pair
            // shift = (3 - pair) * 2. Use a tiny loop building mask/val in $F4.
            // We'll rotate the selector left (6 - pair*2) bits using a table-free loop.
            // shiftcount = 6 - (pair*2):
            //   pair0 ->6, pair1 ->4, pair2 ->2, pair3 ->0
            // Compute via: cnt = 6; repeat pair times: cnt -=2.
            array_push(_list, ["lda_imm", 0x06, _id]);
            array_push(_list, ["label",   "vbmp_plot_shc"]);
            array_push(_list, ["cpx_imm", 0x00, _id]);
            array_push(_list, ["beq",     "vbmp_plot_shd", _id]);
            array_push(_list, ["sec",     0,    _id]);
            array_push(_list, ["sbc_imm", 0x02, _id]);
            array_push(_list, ["dex",     0,    _id]);
            array_push(_list, ["jmp_abs", "vbmp_plot_shc", _id]);
            array_push(_list, ["label",   "vbmp_plot_shd"]);
            array_push(_list, ["sta_zp",  0xF4, _id]); // $F4 = shift count (0,2,4,6)
            // Build shifted selector in A: start sel, ASL $F4 times.
            array_push(_list, ["ldx_zp",  0xF4, _id]); // X = shift count
            array_push(_list, ["lda_zp",  0xF8, _id]); // selector 0..3
            array_push(_list, ["cpx_imm", 0x00, _id]);
            array_push(_list, ["beq",     "vbmp_plot_vshd", _id]);
            array_push(_list, ["label",   "vbmp_plot_vsh"]);
            array_push(_list, ["asl_a",   0,    _id]);
            array_push(_list, ["dex",     0,    _id]);
            array_push(_list, ["bne",     "vbmp_plot_vsh", _id]);
            array_push(_list, ["label",   "vbmp_plot_vshd"]);
            array_push(_list, ["sta_zp",  0xF1, _id]); // $F1 = SHIFTED selector (preserve $F8 for next plot)
            // Build mask 0b11 << shift the same way, into $F4.
            array_push(_list, ["ldx_zp",  0xF4, _id]); // shift count again
            array_push(_list, ["lda_imm", 0x03, _id]);
            array_push(_list, ["cpx_imm", 0x00, _id]);
            array_push(_list, ["beq",     "vbmp_plot_mshd", _id]);
            array_push(_list, ["label",   "vbmp_plot_msh"]);
            array_push(_list, ["asl_a",   0,    _id]);
            array_push(_list, ["dex",     0,    _id]);
            array_push(_list, ["bne",     "vbmp_plot_msh", _id]);
            array_push(_list, ["label",   "vbmp_plot_mshd"]);
            array_push(_list, ["eor_imm", 0xFF, _id]); // A = inverted mask (clear-bits)
            array_push(_list, ["sta_zp",  0xF4, _id]); // $F4 = ~mask
            // read byte, clear pair, OR shifted selector, write back
            array_push(_list, ["ldy_imm", 0x00, _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["and_zp",  0xF4, _id]); // clear the pair
            array_push(_list, ["ora_zp",  0xF1, _id]); // OR shifted selector (from $F1, $F8 preserved)
            array_push(_list, ["sta_izy", 0xF2, _id]);
        } else {
            // HR: single pixel. bit index = 7 - (x & 7). selector 0 = clear, else set.
            array_push(_list, ["lda_zp",  0xF5, _id]);
            array_push(_list, ["and_imm", 0x07, _id]);
            array_push(_list, ["tax",     0,    _id]); // X = x&7
            // shift = 7 - (x&7); build bitmask 0x80 >> (x&7) via LSR loop.
            array_push(_list, ["lda_imm", 0x80, _id]);
            array_push(_list, ["cpx_imm", 0x00, _id]);
            array_push(_list, ["beq",     "vbmp_plot_hrd", _id]);
            array_push(_list, ["label",   "vbmp_plot_hrl"]);
            array_push(_list, ["lsr_a",   0,    _id]);
            array_push(_list, ["dex",     0,    _id]);
            array_push(_list, ["bne",     "vbmp_plot_hrl", _id]);
            array_push(_list, ["label",   "vbmp_plot_hrd"]);
            array_push(_list, ["sta_zp",  0xF4, _id]); // $F4 = bitmask
            array_push(_list, ["ldy_imm", 0x00, _id]);
            // selector 0 -> clear bit, else set bit
            array_push(_list, ["lda_zp",  0xF8, _id]);
            array_push(_list, ["beq",     "vbmp_plot_hrclr", _id]);
            // set
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["ora_zp",  0xF4, _id]);
            array_push(_list, ["sta_izy", 0xF2, _id]);
            array_push(_list, ["jmp_abs", "vbmp_plot_hrend", _id]);
            array_push(_list, ["label",   "vbmp_plot_hrclr"]);
            array_push(_list, ["lda_zp",  0xF4, _id]);
            array_push(_list, ["eor_imm", 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xF4, _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["and_zp",  0xF4, _id]);
            array_push(_list, ["sta_izy", 0xF2, _id]);
            array_push(_list, ["label",   "vbmp_plot_hrend"]);
        }
        array_push(_list, ["rts", 0, _id]);
    
		// ════════════════════════════════════════════════════════════
        // vbmp_ellipse — LUT quarter-arc, two passes (horizontal + vertical).
        // Entry: $EB=cx, $EC=cy, $ED=rx, $EE=ry, $F8=selector.
        //   idx  = axis * 96 / radius        (via vbmp_mul8 + vbmp_div16)
        //   off  = (CIRCLE_Y[idx] * radius) >> 8
        // vbmp_ell_plot4 doubles the x-offset for MC double-wide pixels.
        // Scratch: $EF px/xoff, $F0 yoff/py, $E4 px*2,
        //          $E5/$E8 mul, $E6/$E7 product, $E9 div remainder.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_ellipse"]);
        // ── PASS 1: walk px = 0..rx (horizontal/shallow arc) ──
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEF, _id]);          // px = 0

        array_push(_list, ["label", "vbmp_ell_loop"]);
        array_push(_list, ["lda_zp",  0xEF, _id]);          // A = px
        array_push(_list, ["ldx_imm", 96,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);   // px*96 -> $E6/$E7
        array_push(_list, ["jsr",     "vbmp_div16", _id]);  // /rx -> A
        array_push(_list, ["cmp_imm", 97,   _id]);
        array_push(_list, ["bcc",     "vbmp_ell_idxok", _id]);
        array_push(_list, ["lda_imm", 96,   _id]);
        array_push(_list, ["label", "vbmp_ell_idxok"]);
        array_push(_list, ["tax",     0,    _id]);          // X = idx
        array_push(_list, ["lda_abx", "VBMP_CIRCLE_Y", _id]);
        array_push(_list, ["ldx_zp",  0xEE, _id]);          // X = ry
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);          // yoff = (val*ry)>>8
        array_push(_list, ["sta_zp",  0xF0, _id]);
        array_push(_list, ["jsr",     "vbmp_ell_plot4", _id]);
        // stop one step early so the cardinal point isn't double-plotted by pass 2
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x01, _id]);          // px+1
        array_push(_list, ["cmp_zp",  0xED, _id]);
        array_push(_list, ["bcs",     "vbmp_ell_pass2", _id]); // (px+1) >= rx -> stop
        array_push(_list, ["inc_zp",  0xEF, _id]);
        array_push(_list, ["jmp_abs", "vbmp_ell_loop", _id]);

        // ── PASS 2: walk py = 0..ry (vertical/steep arc) ──
        array_push(_list, ["label", "vbmp_ell_pass2"]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF0, _id]);          // py = 0 (in $F0)

        array_push(_list, ["label", "vbmp_ell_loop2"]);
        array_push(_list, ["lda_zp",  0xF0, _id]);          // A = py
        array_push(_list, ["ldx_imm", 96,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);   // py*96 -> $E6/$E7
        array_push(_list, ["jsr",     "vbmp_div16_ry", _id]); // /ry -> A
        array_push(_list, ["cmp_imm", 97,   _id]);
        array_push(_list, ["bcc",     "vbmp_ell_idxok2", _id]);
        array_push(_list, ["lda_imm", 96,   _id]);
        array_push(_list, ["label", "vbmp_ell_idxok2"]);
        array_push(_list, ["tax",     0,    _id]);          // X = idx
        array_push(_list, ["lda_abx", "VBMP_CIRCLE_Y", _id]);
        array_push(_list, ["ldx_zp",  0xED, _id]);          // X = rx
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);          // xoff = (val*rx)>>8
        array_push(_list, ["sta_zp",  0xEF, _id]);
        array_push(_list, ["jsr",     "vbmp_ell_plot4", _id]);
        // stop one step early so the cardinal point isn't double-plotted by pass 1
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x01, _id]);          // py+1
        array_push(_list, ["cmp_zp",  0xEE, _id]);
        array_push(_list, ["bcs",     "vbmp_ell_done", _id]); // (py+1) >= ry -> stop
        array_push(_list, ["inc_zp",  0xF0, _id]);
        array_push(_list, ["jmp_abs", "vbmp_ell_loop2", _id]);

        array_push(_list, ["label", "vbmp_ell_done"]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_ell_plot4 — plot (cx±xoff*2, cy±yoff). MC width doubled. ──
        array_push(_list, ["label", "vbmp_ell_plot4"]);
        array_push(_list, ["lda_zp",  0xEF, _id]);          // $E4 = xoff * 2 (MC)
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);
        // point 1: cx+x, cy+y
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["adc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["adc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point 2: cx-x, cy+y
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sbc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["adc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point 3: cx+x, cy-y
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["adc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sbc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point 4: cx-x, cy-y
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sbc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sbc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_ellipsefill — solid filled ellipse via horizontal spans. ──
        // Entry: $EB=cx, $EC=cy, $ED=rx, $EE=ry, $F8=selector.
        // For py = 0..ry: xoff = (CIRCLE_Y[idx]*rx)>>8, then plot a span from
        // cx-xoff*2 to cx+xoff*2 at cy+py and cy-py (two mirrored rows).
        // Reuses vbmp_mul8/div16_ry. Span drawn by looping vbmp_plot per MC px.
        array_push(_list, ["label", "vbmp_ellipsefill"]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF0, _id]);          // py = 0

        array_push(_list, ["label", "vbmp_efill_loop"]);
        // idx = py * 96 / ry
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["ldx_imm", 96,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);
        array_push(_list, ["jsr",     "vbmp_div16_ry", _id]);
        array_push(_list, ["cmp_imm", 97,   _id]);
        array_push(_list, ["bcc",     "vbmp_efill_idxok", _id]);
        array_push(_list, ["lda_imm", 96,   _id]);
        array_push(_list, ["label", "vbmp_efill_idxok"]);
        array_push(_list, ["tax",     0,    _id]);
        // xoff = (CIRCLE_Y[idx] * rx) >> 8  -> $EF
        array_push(_list, ["lda_abx", "VBMP_CIRCLE_Y", _id]);
        array_push(_list, ["ldx_zp",  0xED, _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xEF, _id]);          // $EF = xoff (MC half-width)
        // draw the two mirrored spans for this py
        array_push(_list, ["jsr",     "vbmp_efill_span", _id]);
        // py++ ; stop when py > ry
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["cmp_zp",  0xEE, _id]);
        array_push(_list, ["bcs",     "vbmp_efill_done", _id]);
        array_push(_list, ["inc_zp",  0xF0, _id]);
        array_push(_list, ["jmp_abs", "vbmp_efill_loop", _id]);
        array_push(_list, ["label", "vbmp_efill_done"]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_efill_span — plot MC pixels from -xoff to +xoff at cy±py. ──
        // $EF = xoff (0..rx). Walks mc = 0..xoff, plotting 4 points:
        //   (cx+mc*2, cy+py), (cx-mc*2, cy+py), (cx+mc*2, cy-py), (cx-mc*2, cy-py)
        // Uses $E3 as the mc counter (free in this routine).
        array_push(_list, ["label", "vbmp_efill_span"]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE3, _id]);          // mc = 0

        array_push(_list, ["label", "vbmp_efill_sloop"]);
        // $E4 = mc * 2
        array_push(_list, ["lda_zp",  0xE3, _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);
        // point: cx+mc*2, cy+py
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["adc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["adc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point: cx-mc*2, cy+py
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sbc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["adc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point: cx+mc*2, cy-py
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["adc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sbc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // point: cx-mc*2, cy-py
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sbc_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sbc_zp",  0xF0, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // mc++ ; stop when mc > xoff
        array_push(_list, ["lda_zp",  0xE3, _id]);
        array_push(_list, ["cmp_zp",  0xEF, _id]);
        array_push(_list, ["bcs",     "vbmp_efill_sdone", _id]);
        array_push(_list, ["inc_zp",  0xE3, _id]);
        array_push(_list, ["jmp_abs", "vbmp_efill_sloop", _id]);
        array_push(_list, ["label", "vbmp_efill_sdone"]);
        array_push(_list, ["rts", 0, _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_line — Bresenham line from ($E5,$E6) to ($E7,$E8), sel $F8.
        // All coords single-byte (X window 0..255). Uses:
        //   $E5 x0  $E6 y0  $E7 x1  $E8 y1
        //   $E9 dx  $EA dy  $EB sx  $EC sy  $ED err  $EF tmp
        // Plots via vbmp_plot ($F5/$F6 x, $F7 y). MC even-X handled by caller
        // snap, but we also force even X here for safety on stepped points.
        // ════════════════════════════════════════════════════════════
        
		// vbmp_line — unsigned Bresenham, no signed-byte overflow.
        //   $E5 x0  $E6 y0  $E7 x1  $E8 y1  (all 0..255)
        //   $E9 dx  $EA dy  $EB sx (1/$FF)  $EC sy (1/$FF)
        //   $ED err lo  $EF err hi  (16-bit signed err = dx - dy)
        //   $D8 e2 lo   $D9 e2 hi   (e2 = 2*err, 16-bit signed scratch)
        // Steps until (x0,y0) == (x1,y1). All compares done on 16-bit
        // signed values so dx/dy up to 255 never misfire a sign test.
        array_push(_list, ["label", "vbmp_line"]);
        // dx = abs(x1-x0); sx
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["cmp_zp",  0xE5, _id]);
        array_push(_list, ["bcs",     "vbmp_ln_xpos", _id]);
        array_push(_list, ["lda_zp",  0xE5, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["lda_imm", 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xEB, _id]);
        array_push(_list, ["jmp_abs", "vbmp_ln_ydelta", _id]);
        array_push(_list, ["label", "vbmp_ln_xpos"]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xE5, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["lda_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xEB, _id]);
        // dy = abs(y1-y0); sy
        array_push(_list, ["label", "vbmp_ln_ydelta"]);
        array_push(_list, ["lda_zp",  0xE8, _id]);
        array_push(_list, ["cmp_zp",  0xE6, _id]);
        array_push(_list, ["bcs",     "vbmp_ln_ypos", _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xE8, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);
        array_push(_list, ["lda_imm", 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xEC, _id]);
        array_push(_list, ["jmp_abs", "vbmp_ln_err0", _id]);
        array_push(_list, ["label", "vbmp_ln_ypos"]);
        array_push(_list, ["lda_zp",  0xE8, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);
        array_push(_list, ["lda_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xEC, _id]);
        // err = dx - dy  (16-bit signed into $ED/$EF)
        array_push(_list, ["label", "vbmp_ln_err0"]);
        array_push(_list, ["lda_zp",  0xE9, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xEA, _id]);
        array_push(_list, ["sta_zp",  0xED, _id]);          // err lo
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sbc_imm", 0x00, _id]);          // borrow -> $FF, else $00
        array_push(_list, ["sta_zp",  0xEF, _id]);          // err hi (sign extend)

        // main loop
        array_push(_list, ["label", "vbmp_ln_loop"]);
        array_push(_list, ["lda_zp",  0xE5, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        // done? x0==x1 && y0==y1
        array_push(_list, ["lda_zp",  0xE5, _id]);
        array_push(_list, ["cmp_zp",  0xE7, _id]);
        array_push(_list, ["bne",     "vbmp_ln_step", _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["cmp_zp",  0xE8, _id]);
        array_push(_list, ["bne",     "vbmp_ln_step", _id]);
        array_push(_list, ["rts",     0,    _id]);

        array_push(_list, ["label", "vbmp_ln_step"]);
        // e2 = err * 2  (16-bit signed: $D8/$D9 = $ED/$EF << 1)
        array_push(_list, ["lda_zp",  0xED, _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xD8, _id]);          // e2 lo
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["rol_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xD9, _id]);          // e2 hi

        // Condition A: if e2 > -dy  -> err -= dy ; x0 += sx
        // Test (e2 + dy) > 0  i.e.  (e2 + dy) is positive and nonzero.
        // Compute t = e2 + dy (16-bit; dy is 0..255, hi 0). Sign in bit15.
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xD8, _id]);
        array_push(_list, ["adc_zp",  0xEA, _id]);          // t lo = e2lo + dy
        array_push(_list, ["sta_zp",  0xDA, _id]);          // t lo scratch
        array_push(_list, ["lda_zp",  0xD9, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);          // t hi = e2hi + carry
        // A = t hi. If negative (bit7 set) -> skip X. If zero AND t lo zero -> skip (not > 0).
        array_push(_list, ["bmi",     "vbmp_ln_noX", _id]); // t < 0 -> no X step
        // t >= 0: also require t != 0 (strict >). If hi==0 && lo==0 -> skip.
        array_push(_list, ["bne",     "vbmp_ln_doX", _id]); // hi != 0 -> definitely > 0
        array_push(_list, ["lda_zp",  0xDA, _id]);
        array_push(_list, ["beq",     "vbmp_ln_noX", _id]); // t == 0 -> not > 0, skip
        array_push(_list, ["label", "vbmp_ln_doX"]);
        // err -= dy  (16-bit)
        array_push(_list, ["lda_zp",  0xED, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_zp",  0xEA, _id]);
        array_push(_list, ["sta_zp",  0xED, _id]);
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["sbc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEF, _id]);
        // x0 += sx
        array_push(_list, ["lda_zp",  0xE5, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xEB, _id]);
        array_push(_list, ["sta_zp",  0xE5, _id]);
        array_push(_list, ["label", "vbmp_ln_noX"]);

        // Condition B: if e2 < dx  -> err += dx ; y0 += sy
        // Test (e2 - dx) < 0. Compute t = e2 - dx (16-bit signed).
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_zp",  0xD8, _id]);
        array_push(_list, ["sbc_zp",  0xE9, _id]);          // t lo = e2lo - dx
        array_push(_list, ["lda_zp",  0xD9, _id]);
        array_push(_list, ["sbc_imm", 0x00, _id]);          // t hi = e2hi - borrow
        // A = t hi. Negative (bit7) -> e2 < dx -> do Y step.
        array_push(_list, ["bpl",     "vbmp_ln_noY", _id]); // t >= 0 -> skip Y
        // err += dx  (16-bit)
        array_push(_list, ["lda_zp",  0xED, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xE9, _id]);
        array_push(_list, ["sta_zp",  0xED, _id]);
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEF, _id]);
        // y0 += sy
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["label", "vbmp_ln_noY"]);
        array_push(_list, ["jmp_abs", "vbmp_ln_loop", _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_rect — 4-edge outline. Entry $E5 x0 $E6 y0 $E7 x1 $E8 y1.
        // Draws top, bottom, left, right by reusing vbmp_line 4 times.
        // Saves/restores the corners in $F2/$F3/$F4/$EF around each call
        // (vbmp_line clobbers $E5-$ED). sel $F8.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_rect"]);
        // stash the 4 corners in a safe scratch page: $D4-$D7 (free ZP)
        array_push(_list, ["lda_zp",  0xE5, _id]);
        array_push(_list, ["sta_zp",  0xD4, _id]); // x0
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xD5, _id]); // y0
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xD6, _id]); // x1
        array_push(_list, ["lda_zp",  0xE8, _id]);
        array_push(_list, ["sta_zp",  0xD7, _id]); // y1
        // TOP: (x0,y0)-(x1,y0)
        array_push(_list, ["lda_zp",  0xD4, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["lda_zp",  0xD6, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        // BOTTOM: (x0,y1)-(x1,y1)
        array_push(_list, ["lda_zp",  0xD4, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["lda_zp",  0xD7, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["lda_zp",  0xD6, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["lda_zp",  0xD7, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        // LEFT: (x0,y0)-(x0,y1)
        array_push(_list, ["lda_zp",  0xD4, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["lda_zp",  0xD4, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["lda_zp",  0xD7, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        // RIGHT: (x1,y0)-(x1,y1)
        array_push(_list, ["lda_zp",  0xD6, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["lda_zp",  0xD6, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["lda_zp",  0xD7, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        array_push(_list, ["rts",     0,    _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_rectfill — solid box. Entry $E5 x0 $E6 y0 $E7 x1 $E8 y1.
        // For each row y0..y1, draw a horizontal span x0..x1 via vbmp_line.
        // Row counter kept in $D5 (cur y). x0/x1 stashed in $D4/$D6, y1 $D7.
        // Steps rows by +1 (rows are single px tall; MC only affects X pairs).
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_rectfill"]);
        array_push(_list, ["lda_zp",  0xE5, _id]); array_push(_list, ["sta_zp", 0xD4, _id]); // x0
        array_push(_list, ["lda_zp",  0xE7, _id]); array_push(_list, ["sta_zp", 0xD6, _id]); // x1
        array_push(_list, ["lda_zp",  0xE8, _id]); array_push(_list, ["sta_zp", 0xD7, _id]); // y1
        array_push(_list, ["lda_zp",  0xE6, _id]); array_push(_list, ["sta_zp", 0xD5, _id]); // cur y = y0
        array_push(_list, ["label", "vbmp_rf_loop"]);
        // span (x0,cy)-(x1,cy)
        array_push(_list, ["lda_zp",  0xD4, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["lda_zp",  0xD6, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["lda_zp",  0xD5, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        // cy == y1? done
        array_push(_list, ["lda_zp",  0xD5, _id]);
        array_push(_list, ["cmp_zp",  0xD7, _id]);
        array_push(_list, ["bcs",     "vbmp_rf_done", _id]); // cy >= y1 -> stop
        array_push(_list, ["inc_zp",  0xD5, _id]);
        array_push(_list, ["jmp_abs", "vbmp_rf_loop", _id]);
        array_push(_list, ["label", "vbmp_rf_done"]);
        array_push(_list, ["rts",     0,    _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_readpix — read the 2-bit MC value at ($F5/$F6 = x, $F7 = y).
        // Returns the pair value (0..3) in A. Reuses vbmp_plot's address maths
        // but reads instead of writes. Clobbers A,X,Y,$F2,$F3,$F4.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_readpix"]);
        // --- identical byte-address calc to vbmp_plot ---
        array_push(_list, ["lda_zp",  0xF7, _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["tax",     0,    _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF9, _id]);
        array_push(_list, ["adc_abx", "BMPCHARROW_LO", _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xFA, _id]);
        array_push(_list, ["adc_abx", "BMPCHARROW_HI", _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["lda_zp",  0xF7, _id]);
        array_push(_list, ["and_imm", 0x07, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xF2, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xF3, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["lda_zp",  0xF6, _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["lda_zp",  0xF5, _id]);
        array_push(_list, ["ror_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["lda_zp",  0xF6, _id]);
        array_push(_list, ["and_imm", 0x01, _id]);
        array_push(_list, ["beq",     "vbmp_rp_nocolhi", _id]);
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 32,   _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["label",   "vbmp_rp_nocolhi"]);
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xF4, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["rol_a",   0,    _id]);
        array_push(_list, ["pha",     0,    _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF4, _id]);
        array_push(_list, ["adc_zp",  0xF2, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["pla",     0,    _id]);
        array_push(_list, ["adc_zp",  0xF3, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        // --- read the byte, extract the pair (x>>1)&3 from the LEFT ---
        array_push(_list, ["lda_zp",  0xF5, _id]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["and_imm", 0x03, _id]);
        array_push(_list, ["tax",     0,    _id]);          // X = pair 0..3
        // shift count = (3-pair)*2, built via cnt=6; pair times cnt-=2
        array_push(_list, ["lda_imm", 0x06, _id]);
        array_push(_list, ["label",   "vbmp_rp_shc"]);
        array_push(_list, ["cpx_imm", 0x00, _id]);
        array_push(_list, ["beq",     "vbmp_rp_shd", _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_imm", 0x02, _id]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["jmp_abs", "vbmp_rp_shc", _id]);
        array_push(_list, ["label",   "vbmp_rp_shd"]);
        array_push(_list, ["sta_zp",  0xF4, _id]);          // $F4 = shift count
        // read byte, shift right by count, AND 3 -> pair value in A
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["lda_izy", 0xF2, _id]);
        array_push(_list, ["ldx_zp",  0xF4, _id]);
        array_push(_list, ["cpx_imm", 0x00, _id]);
        array_push(_list, ["beq",     "vbmp_rp_shrd", _id]);
        array_push(_list, ["label",   "vbmp_rp_shr"]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_rp_shr", _id]);
        array_push(_list, ["label",   "vbmp_rp_shrd"]);
        array_push(_list, ["and_imm", 0x03, _id]);          // A = pair value 0..3
        array_push(_list, ["rts", 0, _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_fill — scanline flood. Entry: $EB=seed x, $EC=seed y,
        // $F8=fill selector. Matches the seed pixel's colour; fills the
        // connected region. Stack base in $E1/$E2, grows up, 3 bytes/entry
        // (x, 0, y). $E3 = target colour. $EF/$F0 = stack top ptr.
        // MC step = 2 px per pair. X range 0..254, Y range 0..199.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_fill"]);
        // read seed colour -> $E3
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["sta_zp",  0xE3, _id]);          // $E3 = target colour
        // if target == fill selector, nothing to do (avoid infinite loop)
        array_push(_list, ["lda_zp",  0xE3, _id]);
        array_push(_list, ["cmp_zp",  0xF8, _id]);
        array_push(_list, ["bne",     "vbmp_fill_go", _id]);
        array_push(_list, ["rts",     0,    _id]);
        array_push(_list, ["label",   "vbmp_fill_go"]);
        // init stack top ptr = base ($E1/$E2)
        array_push(_list, ["lda_zp",  0xE1, _id]);
        array_push(_list, ["sta_zp",  0xEF, _id]);
        array_push(_list, ["lda_zp",  0xE2, _id]);
        array_push(_list, ["sta_zp",  0xF0, _id]);
        // push seed (x, y)
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);  // push x
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);  // push y

        // main pop loop
        array_push(_list, ["label", "vbmp_fill_pop"]);
        // stack empty? (top == base)
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["cmp_zp",  0xE1, _id]);
        array_push(_list, ["bne",     "vbmp_fill_notempty", _id]);
        array_push(_list, ["lda_zp",  0xF0, _id]);
        array_push(_list, ["cmp_zp",  0xE2, _id]);
        array_push(_list, ["bne",     "vbmp_fill_notempty", _id]);
        array_push(_list, ["rts",     0,    _id]);          // empty -> done
        array_push(_list, ["label",   "vbmp_fill_notempty"]);
        // pop y then x
        array_push(_list, ["jsr",     "vbmp_fpop", _id]);
        array_push(_list, ["sta_zp",  0xEC, _id]);          // $EC = y
        array_push(_list, ["jsr",     "vbmp_fpop", _id]);
        array_push(_list, ["sta_zp",  0xEB, _id]);          // $EB = x

        // check this pixel still matches target (may have been filled)
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["cmp_zp",  0xE3, _id]);
        array_push(_list, ["beq",     "vbmp_fill_scan", _id]);
        array_push(_list, ["jmp_abs", "vbmp_fill_pop", _id]);

        array_push(_list, ["label", "vbmp_fill_scan"]);
        // scan LEFT to find span start: $E4 = leftmost matching x
        array_push(_list, ["lda_zp",  0xEB, _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);          // $E4 = x cursor
        array_push(_list, ["label", "vbmp_fill_left"]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["cmp_imm", 66,  _id]);           // probe is x-2; stop before it goes below 64
        array_push(_list, ["bcc",     "vbmp_fill_ldone", _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_imm", 0x02, _id]);          // x-2
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["cmp_zp",  0xE3, _id]);
        array_push(_list, ["bne",     "vbmp_fill_ldone", _id]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_imm", 0x02, _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);          // move cursor left
        array_push(_list, ["jmp_abs", "vbmp_fill_left", _id]);
        array_push(_list, ["label",   "vbmp_fill_ldone"]);
        // $E4 = span left edge. Fill rightward. $EA/$ED track "already inside a
        // run" flags for above/below so we push only ONE seed per contiguous run.
        //   $EA = above-run flag (0 = not in run, 1 = in run)
        //   $E0 = below-run flag
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);          // above flag = 0
        array_push(_list, ["sta_zp",  0xE0, _id]);          // below flag = 0
        array_push(_list, ["label", "vbmp_fill_right"]);
        // stop if cursor reached window right edge (pre-check, before painting)
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["cmp_imm", 254, _id]);           // x >= 256 (window right edge) -> span done
        array_push(_list, ["bcs",     "vbmp_fill_pop", _id]);
        // read current pixel; stop if not target
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["cmp_zp",  0xE3, _id]);
        array_push(_list, ["beq",     "vbmp_fill_paint", _id]);
        array_push(_list, ["jmp_abs", "vbmp_fill_pop", _id]); // span done
        array_push(_list, ["label", "vbmp_fill_paint"]);
        // Select the paint colour for this pixel based on dither pattern ($D0):
        //   0 solid    -> colA ($F8)
        //   1 checker  -> ((x>>1) + y) & 1 ? colB : colA
        //   2 interlace-> (y & 1)          ? colB : colA
        // colA = $F8, colB = $D2. Chosen colour parked in $D1 (temp selector).
        // $F8 must be preserved (SETCOL tracking relies on it), so plot reads
        // its selector from $D1 via a swap around the plot call.
        array_push(_list, ["lda_zp",  0xD0, _id]);
        array_push(_list, ["cmp_imm", 0x00, _id]);
        array_push(_list, ["bne",     "vbmp_fp_dith", _id]);
        // solid -> colA
        array_push(_list, ["lda_zp",  0xF8, _id]);
        array_push(_list, ["sta_zp",  0xD1, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fp_doplot", _id]);
        array_push(_list, ["label", "vbmp_fp_dith"]);
        array_push(_list, ["cmp_imm", 0x02, _id]);
        array_push(_list, ["beq",     "vbmp_fp_interlace", _id]);
        // checker: parity = ((x>>1) + y) & 1. x is in $E4.
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["lsr_a",   0,    _id]); // x>>1
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xEC, _id]); // + y
        array_push(_list, ["and_imm", 0x01, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fp_pick", _id]);
        array_push(_list, ["label", "vbmp_fp_interlace"]);
        // interlace: parity = y & 1
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["and_imm", 0x01, _id]);
        array_push(_list, ["label", "vbmp_fp_pick"]);
        array_push(_list, ["beq",     "vbmp_fp_useA", _id]);
        // parity 1 -> colB
        array_push(_list, ["lda_zp",  0xD2, _id]);
        array_push(_list, ["sta_zp",  0xD1, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fp_doplot", _id]);
        array_push(_list, ["label", "vbmp_fp_useA"]);
        array_push(_list, ["lda_zp",  0xF8, _id]);
        array_push(_list, ["sta_zp",  0xD1, _id]);
        // Plot using the chosen selector: swap $D1 into $F8, plot, restore $F8.
        array_push(_list, ["label", "vbmp_fp_doplot"]);
        array_push(_list, ["lda_zp",  0xF8, _id]);
        array_push(_list, ["pha",     0,    _id]); // save real colA
        array_push(_list, ["lda_zp",  0xD1, _id]);
        array_push(_list, ["sta_zp",  0xF8, _id]); // temp selector for plot
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        array_push(_list, ["pla",     0,    _id]);
        array_push(_list, ["sta_zp",  0xF8, _id]); // restore real colA

        // ── ABOVE (y-1) run tracking ──
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["cmp_imm", 41,   _id]);
        array_push(_list, ["bcs",     "vbmp_fill_up_ck", _id]); // y>=41 (above still in window) -> check
        // y==0: force above flag off, skip
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fill_dn", _id]);
        array_push(_list, ["label", "vbmp_fill_up_ck"]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["cmp_zp",  0xE3, _id]);
        array_push(_list, ["bne",     "vbmp_fill_up_off", _id]); // not target -> run ends
        // pixel above IS target. Push a seed only if we weren't already in a run.
        array_push(_list, ["lda_zp",  0xEA, _id]);
        array_push(_list, ["bne",     "vbmp_fill_dn", _id]);     // already in run -> no push
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["sbc_imm", 0x01, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);
        array_push(_list, ["lda_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);               // now in run
        array_push(_list, ["jmp_abs", "vbmp_fill_dn", _id]);
        array_push(_list, ["label", "vbmp_fill_up_off"]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xEA, _id]);               // run ended

        // ── BELOW (y+1) run tracking ──
        array_push(_list, ["label", "vbmp_fill_dn"]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["cmp_imm", 160, _id]);
        array_push(_list, ["bcc",     "vbmp_fill_dn_ck", _id]);  // y<160 (window bottom edge) -> check

        // y>=160: force below flag off, skip
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE0, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fill_adv", _id]);
        array_push(_list, ["label", "vbmp_fill_dn_ck"]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xF7, _id]);
        array_push(_list, ["jsr",     "vbmp_readpix", _id]);
        array_push(_list, ["cmp_zp",  0xE3, _id]);
        array_push(_list, ["bne",     "vbmp_fill_dn_off", _id]);
        array_push(_list, ["lda_zp",  0xE0, _id]);
        array_push(_list, ["bne",     "vbmp_fill_adv", _id]);    // already in run
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);
        array_push(_list, ["lda_zp",  0xEC, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x01, _id]);
        array_push(_list, ["jsr",     "vbmp_fpush", _id]);
        array_push(_list, ["lda_imm", 0x01, _id]);
        array_push(_list, ["sta_zp",  0xE0, _id]);
        array_push(_list, ["jmp_abs", "vbmp_fill_adv", _id]);
        array_push(_list, ["label", "vbmp_fill_dn_off"]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE0, _id]);

        // advance cursor right by 2 (MC step)
        array_push(_list, ["label", "vbmp_fill_adv"]);
        array_push(_list, ["lda_zp",  0xE4, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x02, _id]);
        array_push(_list, ["sta_zp",  0xE4, _id]);
        array_push(_list, ["cmp_imm", 254, _id]);           // x >= 254 (window right edge) -> stop
        array_push(_list, ["bcc",     "vbmp_fill_adv_go", _id]); // still in range -> keep scanning
        array_push(_list, ["jmp_abs", "vbmp_fill_pop", _id]);    // out of window -> span done (far jump)
        array_push(_list, ["label",   "vbmp_fill_adv_go"]);
        array_push(_list, ["jmp_abs", "vbmp_fill_right", _id]);

        // ── vbmp_fpush — push A onto fill stack at ($EF/$F0), bump ptr. ──
        // Overflow guard: the stack lives at base..base+$07FF (2KB), with the
        // command stream at base+$0800. If the write pointer high byte reaches
        // (base_hi + 7), we are within the last page before the stream — drop
        // the seed rather than overrun the stream. A dropped seed leaves a tiny
        // unfilled pocket, which is far safer than corrupting stream/code (hang).
        array_push(_list, ["label", "vbmp_fpush"]);
        array_push(_list, ["pha",     0,    _id]);          // save value to push
        // ceil_hi = $E2 (base hi) + 7
        array_push(_list, ["lda_zp",  0xE2, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_imm", 0x07, _id]);
        array_push(_list, ["cmp_zp",  0xF0, _id]);          // ceil_hi - ptr_hi
        array_push(_list, ["bne",     "vbmp_fpush_ok", _id]); // not on last page -> ok
        // ptr_hi == ceil_hi: we are in the final page before stream -> drop.
        array_push(_list, ["pla",     0,    _id]);          // discard value
        array_push(_list, ["rts",     0,    _id]);
        array_push(_list, ["label", "vbmp_fpush_ok"]);
        array_push(_list, ["pla",     0,    _id]);          // restore value
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["sta_izy", 0xEF, _id]);
        array_push(_list, ["inc_zp",  0xEF, _id]);
        array_push(_list, ["bne",     "vbmp_fpush_done", _id]);
        array_push(_list, ["inc_zp",  0xF0, _id]);
        array_push(_list, ["label",   "vbmp_fpush_done"]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_fpop — decrement ptr, pop byte from ($EF/$F0) into A. ──
        array_push(_list, ["label", "vbmp_fpop"]);
        array_push(_list, ["lda_zp",  0xEF, _id]);
        array_push(_list, ["bne",     "vbmp_fpop_nohi", _id]);
        array_push(_list, ["dec_zp",  0xF0, _id]);
        array_push(_list, ["label",   "vbmp_fpop_nohi"]);
        array_push(_list, ["dec_zp",  0xEF, _id]);
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["lda_izy", 0xEF, _id]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_mul8 — A * X -> $E6 lo / $E7 hi. Clobbers A,X,Y,$E5,$E8. ──
        array_push(_list, ["label", "vbmp_mul8"]);
        array_push(_list, ["sta_zp",  0xE5, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE8, _id]);
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);
        array_push(_list, ["txa",     0,    _id]);
        array_push(_list, ["beq",     "vbmp_mul8_done", _id]);
        array_push(_list, ["ldy_imm", 0x08, _id]);
        array_push(_list, ["label", "vbmp_mul8_lp"]);
        array_push(_list, ["lsr_a",   0,    _id]);
        array_push(_list, ["bcc",     "vbmp_mul8_no", _id]);
        array_push(_list, ["pha",     0,    _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["adc_zp",  0xE5, _id]);
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_zp",  0xE8, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);
        array_push(_list, ["pla",     0,    _id]);
        array_push(_list, ["label", "vbmp_mul8_no"]);
        array_push(_list, ["pha",     0,    _id]);
        array_push(_list, ["asl_zp",  0xE5, _id]);
        array_push(_list, ["rol_zp",  0xE8, _id]);
        array_push(_list, ["pla",     0,    _id]);
        array_push(_list, ["dey",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_mul8_lp", _id]);
        array_push(_list, ["label", "vbmp_mul8_done"]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_div16 — 16÷8. Dividend $E6/$E7, divisor $ED (rx). Q -> A. ──
        // Round-to-nearest: pre-add rx/2 to the dividend so the quotient
        // rounds instead of truncating (tighter match to editor curve).
        array_push(_list, ["label", "vbmp_div16"]);
        array_push(_list, ["lda_zp",  0xED, _id]);          // rx
        array_push(_list, ["lsr_a",   0,    _id]);          // rx/2
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);          // dividend lo += rx/2
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["ldx_imm", 16,   _id]);
        array_push(_list, ["label", "vbmp_div16_lp"]);
        array_push(_list, ["asl_zp",  0xE6, _id]);
        array_push(_list, ["rol_zp",  0xE7, _id]);
        array_push(_list, ["rol_zp",  0xE9, _id]);
        array_push(_list, ["lda_zp",  0xE9, _id]);
        array_push(_list, ["cmp_zp",  0xED, _id]);
        array_push(_list, ["bcc",     "vbmp_div16_skip", _id]);
        array_push(_list, ["sbc_zp",  0xED, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["inc_zp",  0xE6, _id]);
        array_push(_list, ["label", "vbmp_div16_skip"]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_div16_lp", _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["rts", 0, _id]);

        // ── vbmp_div16_ry — 16÷8. Dividend $E6/$E7, divisor $EE (ry). Q -> A. ──
        // Round-to-nearest: pre-add ry/2 to the dividend.
        array_push(_list, ["label", "vbmp_div16_ry"]);
        array_push(_list, ["lda_zp",  0xEE, _id]);          // ry
        array_push(_list, ["lsr_a",   0,    _id]);          // ry/2
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);          // dividend lo += ry/2
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["ldx_imm", 16,   _id]);
        array_push(_list, ["label", "vbmp_div16_ry_lp"]);
        array_push(_list, ["asl_zp",  0xE6, _id]);
        array_push(_list, ["rol_zp",  0xE7, _id]);
        array_push(_list, ["rol_zp",  0xE9, _id]);
        array_push(_list, ["lda_zp",  0xE9, _id]);
        array_push(_list, ["cmp_zp",  0xEE, _id]);
        array_push(_list, ["bcc",     "vbmp_div16_ry_skip", _id]);
        array_push(_list, ["sbc_zp",  0xEE, _id]);
        array_push(_list, ["sta_zp",  0xE9, _id]);
        array_push(_list, ["inc_zp",  0xE6, _id]);
        array_push(_list, ["label", "vbmp_div16_ry_skip"]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_div16_ry_lp", _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["rts", 0, _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_render — the interpreter.
        // Entry: $FB/$FC = stream ptr, $F9/$FA = bmp_base (set by caller).
        // Walks opcodes until $00 END. STAGE 1: $00 END, $01 PLOT, $0A SETCOL.
        // Reads stream via (zp),Y with Y advancing; when Y would exceed the
        // page we bump $FC and reset Y — but for simplicity each opcode reads
        // sequentially and rebases the pointer after consuming its bytes.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_render"]);
        array_push(_list, ["ldy_imm", 0x00, _id]); // we always read at Y=0 then advance ptr

        array_push(_list, ["label", "vbmp_render_loop"]);
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // opcode
        // END?
        array_push(_list, ["cmp_imm", 0x00, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_end", _id]);
        array_push(_list, ["rts",     0,    _id]);
        array_push(_list, ["label",   "vbmp_render_not_end"]);

        // SETCOL ($0A) — 1 arg byte -> $F8. advance ptr by 2.
        array_push(_list, ["cmp_imm", 0x0A, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_setcol", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]);
        array_push(_list, ["and_imm", 0x03, _id]);
        array_push(_list, ["sta_zp",  0xF8, _id]);
        // advance ptr += 2
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x02, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_setcol"]);

        // PLOT ($01) — args x.w y.b  (3 arg bytes). advance ptr by 4.
        array_push(_list, ["cmp_imm", 0x01, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_plot", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // x lo
        array_push(_list, ["sta_zp",  0xF5, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // x hi
        array_push(_list, ["sta_zp",  0xF6, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // y
        array_push(_list, ["sta_zp",  0xF7, _id]);
        // advance ptr += 4 BEFORE plot (plot preserves $FB/$FC anyway, but do it first)
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x04, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_plot", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_plot"]);

        // LINE ($02) — args x0 y0 x1 y1 (4 arg bytes). advance ptr by 5.
        array_push(_list, ["cmp_imm", 0x02, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_line", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE5, _id]); // x0
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE6, _id]); // y0
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE7, _id]); // x1
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE8, _id]); // y1
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_line", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_line"]);

        // RECT ($03) — args x0 y0 x1 y1 (4 arg bytes). advance ptr by 5.
        array_push(_list, ["cmp_imm", 0x03, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_rect", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_rect", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_rect"]);

        // RECTFILL ($04) — args x0 y0 x1 y1 (4 arg bytes). advance ptr by 5.
        array_push(_list, ["cmp_imm", 0x04, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_rectfill", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE5, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE6, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE7, _id]);
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE8, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_rectfill", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_rectfill"]);

        // ELLIPSE ($05) — args cx cy rx ry (4 arg bytes). advance ptr by 5.
        array_push(_list, ["cmp_imm", 0x05, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_ellipse", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // cx
        array_push(_list, ["sta_zp",  0xEB, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // cy
        array_push(_list, ["sta_zp",  0xEC, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // rx
        array_push(_list, ["sta_zp",  0xED, _id]);
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // ry
        array_push(_list, ["sta_zp",  0xEE, _id]);
        // advance ptr += 5
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_ellipse", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_ellipse"]);

        // ELLIPSEFILL ($06) — args cx cy rx ry (4 arg bytes). advance ptr by 5.
        array_push(_list, ["cmp_imm", 0x06, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_efill", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // cx
        array_push(_list, ["sta_zp",  0xEB, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // cy
        array_push(_list, ["sta_zp",  0xEC, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // rx
        array_push(_list, ["sta_zp",  0xED, _id]);
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // ry
        array_push(_list, ["sta_zp",  0xEE, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_ellipsefill", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_efill"]);

        // FILL ($07) — args cx cy pattern colB (4 arg bytes). advance ptr by 5.
        // pattern -> $D0 (0 solid, 1 checker, 2 interlace). colB -> $D2 (second
        // dither colour 0..3). colA is the active selector $F8. Both colours are
        // explicit per-command, so no setcol-run heuristic.
        array_push(_list, ["cmp_imm", 0x07, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_fill", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // seed x
        array_push(_list, ["sta_zp",  0xEB, _id]);
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // seed y
        array_push(_list, ["sta_zp",  0xEC, _id]);
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // pattern
        array_push(_list, ["sta_zp",  0xD0, _id]); // $D0 = dither pattern
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); // colB
        array_push(_list, ["and_imm", 0x03, _id]);
        array_push(_list, ["sta_zp",  0xD2, _id]); // $D2 = second dither colour
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x05, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_fill", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_fill"]);

        // RECOLOR CRAM ($08) — col row w h col3. Writes col3 into colour RAM
        // ($D800 + row*40 + col) across the w×h cell block. ptr += 6.
        array_push(_list, ["cmp_imm", 0x08, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_crecol", _id]);
        array_push(_list, ["jsr",     "vbmp_recol_args", _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_imm", 0xD8, _id]);
        array_push(_list, ["adc_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["jsr",     "vbmp_recol_fill", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_crecol"]);

        // RECOLOR SRAM ($09) — col row w h scrval. Writes (col1<<4)|col2 into
        // screen RAM (base $DB/$DC + row*40 + col) across the block. ptr += 6.
        array_push(_list, ["cmp_imm", 0x09, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_srecol", _id]);
        array_push(_list, ["jsr",     "vbmp_recol_args", _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xDB, _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xDC, _id]);
        array_push(_list, ["adc_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["jsr",     "vbmp_recol_fill", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_srecol"]);

        // COPYREGION ($0B) — sc sr dc dr w h. Duplicates a w×h cell block
        // (bitmap 8 bytes/cell + screen RAM + colour RAM) from source cell
        // (sc,sr) to dest cell (dc,dr). Reads args into $C0-$C5, then JSRs
        // vbmp_copyregion. ptr += 7.
        array_push(_list, ["cmp_imm", 0x0B, _id]);
        array_push(_list, ["bne",     "vbmp_render_not_copyrgn", _id]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC0, _id]); // sc
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC1, _id]); // sr
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC2, _id]); // dc
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC3, _id]); // dr
        array_push(_list, ["ldy_imm", 0x05, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC4, _id]); // w
        array_push(_list, ["ldy_imm", 0x06, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xC5, _id]); // h
        // advance ptr += 7
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x07, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        array_push(_list, ["jsr",     "vbmp_copyregion", _id]);
        array_push(_list, ["jmp_abs", "vbmp_render_loop", _id]);
        array_push(_list, ["label",   "vbmp_render_not_copyrgn"]);

        // Unknown opcode — bail to avoid runaway. RTS.
        array_push(_list, ["rts", 0, _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_clear — wipe the 8000-byte bitmap at bmp_base ($F9/$FA).
        // Used by the setup node (before page-0 render) and by every
        // MACRO_VECTOR_PAGE node (before re-rendering the chosen page).
        // Writes $00 across 8192 bytes (32 pages) covering the 8000-byte
        // bitmap; the trailing 192 bytes spill harmlessly into the char
        // area below screen RAM (bank layout leaves them unused here).
        // Clobbers A,X,Y,$F2/$F3. Preserves bmp_base in $F9/$FA.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_clear"]);
        array_push(_list, ["lda_zp",  0xF9, _id]);          // $F2/$F3 = bmp_base
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xFA, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["ldx_imm", 0x20, _id]);          // 32 pages = 8192 bytes
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["label",   "vbmp_clear_lp"]);
        array_push(_list, ["sta_izy", 0xF2, _id]);
        array_push(_list, ["iny",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_clear_lp", _id]);
        array_push(_list, ["inc_zp",  0xF3, _id]);          // next page
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_clear_lp", _id]);
        array_push(_list, ["rts",     0,    _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_recol_args — read a recolour command's 5 args, advance the
        // stream ptr past the 6-byte opcode, pre-compute the cell offset.
        // Entry: $FB/$FC -> opcode byte. Reads [col,row,w,h,colval] at +1..+5.
        //   $D4=col $D6=w $D7=h $E3=colval | $E6/$E7=row*40+col | $E5=40-w
        // Clobbers A,X,Y,$D5,$E8. Preserves $F8/$F9/$FA/$D0/$D2/$DB/$DC.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_recol_args"]);
        array_push(_list, ["ldy_imm", 0x01, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xD4, _id]); // col
        array_push(_list, ["ldy_imm", 0x02, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xD5, _id]); // row
        array_push(_list, ["ldy_imm", 0x03, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xD6, _id]); // w
        array_push(_list, ["ldy_imm", 0x04, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xD7, _id]); // h
        array_push(_list, ["ldy_imm", 0x05, _id]);
        array_push(_list, ["lda_izy", 0xFB, _id]); array_push(_list, ["sta_zp", 0xE3, _id]); // colval
        // advance ptr += 6
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xFB, _id]);
        array_push(_list, ["adc_imm", 0x06, _id]);
        array_push(_list, ["sta_zp",  0xFB, _id]);
        array_push(_list, ["lda_zp",  0xFC, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xFC, _id]);
        // row*40 -> $E6/$E7
        array_push(_list, ["lda_zp",  0xD5, _id]);
        array_push(_list, ["ldx_imm", 40,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);
        // += col (16-bit)
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["adc_zp",  0xD4, _id]);
        array_push(_list, ["sta_zp",  0xE6, _id]);
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);
        // $E5 = 40 - w
        array_push(_list, ["sec",     0,    _id]);
        array_push(_list, ["lda_imm", 40,   _id]);
        array_push(_list, ["sbc_zp",  0xD6, _id]);
        array_push(_list, ["sta_zp",  0xE5, _id]);
        array_push(_list, ["rts",     0,    _id]);

        // ════════════════════════════════════════════════════════════
        // vbmp_recol_fill — write $E3 across a w×h cell block.
        // Entry: $F2/$F3=start addr, $D6=w, $D7=h, $E3=colval, $E5=40-w.
        // Y held at 0; ptr walked directly. Clobbers A,X,Y,$D7,$F2,$F3.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_recol_fill"]);
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["label", "vbmp_recol_row"]);
        array_push(_list, ["ldx_zp",  0xD6, _id]);          // X = w
        array_push(_list, ["label", "vbmp_recol_col"]);
        array_push(_list, ["lda_zp",  0xE3, _id]);
        array_push(_list, ["sta_izy", 0xF2, _id]);
        array_push(_list, ["inc_zp",  0xF2, _id]);
        array_push(_list, ["bne",     "vbmp_recol_nc", _id]);
        array_push(_list, ["inc_zp",  0xF3, _id]);
        array_push(_list, ["label", "vbmp_recol_nc"]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_recol_col", _id]);
        // end of row: ptr += (40 - w) to reach next row start
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF2, _id]);
        array_push(_list, ["adc_zp",  0xE5, _id]);
        array_push(_list, ["sta_zp",  0xF2, _id]);
        array_push(_list, ["lda_zp",  0xF3, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xF3, _id]);
        array_push(_list, ["dec_zp",  0xD7, _id]);
        array_push(_list, ["bne",     "vbmp_recol_row", _id]);
        array_push(_list, ["rts",     0,    _id]);
		
		// ════════════════════════════════════════════════════════════
        // vbmp_copyregion — duplicate a w×h cell block (bitmap 8 bytes/
        // cell + screen RAM + colour RAM) from source (sc,sr) to dest
        // (dc,dr). Args in $C0=sc $C1=sr $C2=dc $C3=dr $C4=w $C5=h.
        // No overlap handling — dest must not overlap source. Walks cell
        // rows top→bottom, cells left→right; bitmap row base looked up
        // once per cell-row via BMPCHARROW, col*8 added per cell.
        // Scratch:
        //   $C6 row counter (h down)   $C7 col counter (w down)
        //   $C8 cur src row  $C9 cur dst row  (advance each cell-row)
        //   $CA/$CB src bitmap ptr     $CC/$CD dst bitmap ptr
        //   $CE src cell offset lo (row*40+col, 16-bit uses $CE/$CF? no:
        //       screen/colour offset fits differently — see below)
        // Clobbers A,X,Y and $C6-$CF, $F2/$F3.
        // ════════════════════════════════════════════════════════════
        array_push(_list, ["label", "vbmp_copyregion"]);
        // init per-copy row cursors
        array_push(_list, ["lda_zp",  0xC1, _id]); array_push(_list, ["sta_zp", 0xC8, _id]); // cur src row = sr
        array_push(_list, ["lda_zp",  0xC3, _id]); array_push(_list, ["sta_zp", 0xC9, _id]); // cur dst row = dr
        // row counter = h
        array_push(_list, ["lda_zp",  0xC5, _id]); array_push(_list, ["sta_zp", 0xC6, _id]);
        // Driver loop: JSR the one-row worker, advance cursors, repeat. Kept
        // deliberately SMALL so the backward BNE stays within 6502 relative
        // range (the full per-row body is ~250 bytes — far beyond +/-127 —
        // so it MUST live behind a JSR, not inline under the loop branch).
        array_push(_list, ["label", "vbmp_cr_rowlp"]);
        array_push(_list, ["jsr",     "vbmp_cr_onerow", _id]);
        array_push(_list, ["inc_zp",  0xC8, _id]);          // src row++
        array_push(_list, ["inc_zp",  0xC9, _id]);          // dst row++
        array_push(_list, ["dec_zp",  0xC6, _id]);
        array_push(_list, ["bne",     "vbmp_cr_rowlp", _id]); // short backward branch now
        array_push(_list, ["rts",     0,    _id]);
        // ── one-row worker: copies a single cell-row (CRAM + SCRAM + bitmap)
        //    for the current $C8 (src row) / $C9 (dst row). RTS back to driver.
        array_push(_list, ["label", "vbmp_cr_onerow"]);

        // ── COLOUR + SCREEN RAM for this cell-row ──
        // src cell offset = srcrow*40 + sc  -> $F2/$F3 (reuse for both RAMs)
        array_push(_list, ["lda_zp",  0xC8, _id]);          // cur src row
        array_push(_list, ["ldx_imm", 40,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);   // -> $E6/$E7
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["adc_zp",  0xC0, _id]);          // + sc
        array_push(_list, ["sta_zp",  0xCE, _id]);          // src celloff lo
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xCF, _id]);          // src celloff hi
        // dst cell offset = dstrow*40 + dc -> $E6/$E7 (kept)
        array_push(_list, ["lda_zp",  0xC9, _id]);          // cur dst row
        array_push(_list, ["ldx_imm", 40,   _id]);
        array_push(_list, ["jsr",     "vbmp_mul8", _id]);   // -> $E6/$E7
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xE6, _id]);
        array_push(_list, ["adc_zp",  0xC2, _id]);          // + dc
        array_push(_list, ["sta_zp",  0xE6, _id]);          // dst celloff lo
        array_push(_list, ["lda_zp",  0xE7, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xE7, _id]);          // dst celloff hi

        // COLOUR RAM: src = $D800 + srcoff, dst = $D800 + dstoff. Copy w bytes.
        // src ptr -> $CA/$CB, dst ptr -> $CC/$CD.
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["adc_zp",  0xCE, _id]);
        array_push(_list, ["sta_zp",  0xCA, _id]);
        array_push(_list, ["lda_imm", 0xD8, _id]);
        array_push(_list, ["adc_zp",  0xCF, _id]);
        array_push(_list, ["sta_zp",  0xCB, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xCC, _id]);
        array_push(_list, ["lda_imm", 0xD8, _id]);
        array_push(_list, ["adc_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xCD, _id]);
        array_push(_list, ["ldx_zp",  0xC4, _id]);          // X = w
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["label", "vbmp_cr_cramlp"]);
        array_push(_list, ["lda_izy", 0xCA, _id]);
        array_push(_list, ["sta_izy", 0xCC, _id]);
        array_push(_list, ["iny",     0,    _id]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_cr_cramlp", _id]);

        // SCREEN RAM: src = scrbase($DB/$DC) + srcoff, dst = scrbase + dstoff.
        // Rebuild src ptr -> $CA/$CB, dst ptr -> $CC/$CD from scrbase.
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xDB, _id]);
        array_push(_list, ["adc_zp",  0xCE, _id]);
        array_push(_list, ["sta_zp",  0xCA, _id]);
        array_push(_list, ["lda_zp",  0xDC, _id]);
        array_push(_list, ["adc_zp",  0xCF, _id]);
        array_push(_list, ["sta_zp",  0xCB, _id]);
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xDB, _id]);
        array_push(_list, ["adc_zp",  0xE6, _id]);
        array_push(_list, ["sta_zp",  0xCC, _id]);
        array_push(_list, ["lda_zp",  0xDC, _id]);
        array_push(_list, ["adc_zp",  0xE7, _id]);
        array_push(_list, ["sta_zp",  0xCD, _id]);
        array_push(_list, ["ldx_zp",  0xC4, _id]);          // X = w
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["label", "vbmp_cr_scramlp"]);
        array_push(_list, ["lda_izy", 0xCA, _id]);
        array_push(_list, ["sta_izy", 0xCC, _id]);
        array_push(_list, ["iny",     0,    _id]);
        array_push(_list, ["dex",     0,    _id]);
        array_push(_list, ["bne",     "vbmp_cr_scramlp", _id]);

        // ── BITMAP for this cell-row ──
        // src bitmap row base = bmp_base + BMPCHARROW[srcrow] -> $CA/$CB
        array_push(_list, ["ldx_zp",  0xC8, _id]);          // X = src row
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF9, _id]);          // bmp_base lo
        array_push(_list, ["adc_abx", "BMPCHARROW_LO", _id]);
        array_push(_list, ["sta_zp",  0xCA, _id]);
        array_push(_list, ["lda_zp",  0xFA, _id]);          // bmp_base hi
        array_push(_list, ["adc_abx", "BMPCHARROW_HI", _id]);
        array_push(_list, ["sta_zp",  0xCB, _id]);
        // dst bitmap row base = bmp_base + BMPCHARROW[dstrow] -> $CC/$CD
        array_push(_list, ["ldx_zp",  0xC9, _id]);          // X = dst row
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xF9, _id]);
        array_push(_list, ["adc_abx", "BMPCHARROW_LO", _id]);
        array_push(_list, ["sta_zp",  0xCC, _id]);
        array_push(_list, ["lda_zp",  0xFA, _id]);
        array_push(_list, ["adc_abx", "BMPCHARROW_HI", _id]);
        array_push(_list, ["sta_zp",  0xCD, _id]);
        // add src col*8: (sc<<3) 16-bit into $CA/$CB
        array_push(_list, ["lda_zp",  0xC0, _id]);          // sc
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);          // sc*8 lo (sc<=39 -> max 312)
        array_push(_list, ["sta_zp",  0xC7, _id]);          // $C7 = tmp lo
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["rol_a",   0,    _id]);          // carry -> hi
        array_push(_list, ["sta_zp",  0xD3, _id]);          // $D3 = tmp hi (NOT $E6 — mul8 owns $E6)
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xCA, _id]);
        array_push(_list, ["adc_zp",  0xC7, _id]);
        array_push(_list, ["sta_zp",  0xCA, _id]);
        array_push(_list, ["lda_zp",  0xCB, _id]);
        array_push(_list, ["adc_zp",  0xD3, _id]);
        array_push(_list, ["sta_zp",  0xCB, _id]);
        // add dst col*8: (dc<<3) 16-bit into $CC/$CD
        array_push(_list, ["lda_zp",  0xC2, _id]);          // dc
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["asl_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xC7, _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["rol_a",   0,    _id]);
        array_push(_list, ["sta_zp",  0xD3, _id]);          // $D3 = tmp hi (NOT $E6)
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xCC, _id]);
        array_push(_list, ["adc_zp",  0xC7, _id]);
        array_push(_list, ["sta_zp",  0xCC, _id]);
        array_push(_list, ["lda_zp",  0xCD, _id]);
        array_push(_list, ["adc_zp",  0xD3, _id]);
        array_push(_list, ["sta_zp",  0xCD, _id]);

        // Copy w cells × 8 bytes. $CA/$CB walk src, $CC/$CD walk dst; both
        // advance by 8 per cell (cells are contiguous in bitmap: col*8 steps).
        array_push(_list, ["lda_zp",  0xC4, _id]); array_push(_list, ["sta_zp", 0xC7, _id]); // col counter = w
        array_push(_list, ["label", "vbmp_cr_bmpcell"]);
        array_push(_list, ["ldy_imm", 0x00, _id]);
        array_push(_list, ["label", "vbmp_cr_bmpbyte"]);
        array_push(_list, ["lda_izy", 0xCA, _id]);
        array_push(_list, ["sta_izy", 0xCC, _id]);
        array_push(_list, ["iny",     0,    _id]);
        array_push(_list, ["cpy_imm", 0x08, _id]);
        array_push(_list, ["bne",     "vbmp_cr_bmpbyte", _id]);
        // advance src ptr += 8
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xCA, _id]);
        array_push(_list, ["adc_imm", 0x08, _id]);
        array_push(_list, ["sta_zp",  0xCA, _id]);
        array_push(_list, ["lda_zp",  0xCB, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xCB, _id]);
        // advance dst ptr += 8
        array_push(_list, ["clc",     0,    _id]);
        array_push(_list, ["lda_zp",  0xCC, _id]);
        array_push(_list, ["adc_imm", 0x08, _id]);
        array_push(_list, ["sta_zp",  0xCC, _id]);
        array_push(_list, ["lda_zp",  0xCD, _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_zp",  0xCD, _id]);
        array_push(_list, ["dec_zp",  0xC7, _id]);
        array_push(_list, ["bne",     "vbmp_cr_bmpcell", _id]);

        // ── end of one-row worker: return to driver, which advances the
        //    row cursors and re-enters. (Row-advance moved to the driver so
        //    the loop's backward branch stays in range.)
        array_push(_list, ["rts",     0,    _id]);

        array_push(_list, ["label", "vbmp_rt_skip"]);
    } // end shared runtime

    // ════════════════════════════════════════════════════════════════
    // PER-NODE: set bmp_base in $F9/$FA, stream ptr in $FB/$FC, JSR render.
    // ════════════════════════════════════════════════════════════════
    // RENDER NOW removed — a VECTOR_BMP node always renders when hit on the spine.
    if (true) {
        // ── Resolve palette + screen/colour RAM for MCB colour fill ──
        // Page 0's palette must come from its STORED page entry (pages[0]), not
        // the live meta scratch (_vm.bg/col1/...). The scratch mirrors whichever
        // page the editor is currently viewing, so reading it here makes page 0
        // render with the viewed page's colours. Fall back to _vm.* only when the
        // asset has no pages array (legacy single-page assets).
        var _pal_src = _vm;
        if (variable_struct_exists(_vm, "pages") && is_array(_vm.pages) && array_length(_vm.pages) > 0) {
            _pal_src = _vm.pages[0];
        }
        var _vb_bg   = variable_struct_exists(_pal_src, "bg")   ? (real(_pal_src.bg)   & 0x0F) : 0;
        var _vb_col1 = variable_struct_exists(_pal_src, "col1") ? (real(_pal_src.col1) & 0x0F) : 1;
        var _vb_col2 = variable_struct_exists(_pal_src, "col2") ? (real(_pal_src.col2) & 0x0F) : 2;
        var _vb_col3 = variable_struct_exists(_pal_src, "col3") ? (real(_pal_src.col3) & 0x0F) : 3;
        // Screen RAM: derive from bmp_base's VIC bank. MCB screen RAM sits in
        // the same 16K bank. Use $6000 (bank 1) unless meta overrides.
        var _scr_ram = variable_struct_exists(_vm, "screen_ram") ? real(_vm.screen_ram) : 0x6000;
        var _scr_val = ((_vb_col1 << 4) | _vb_col2) & 0xFF; // sel1=hi nibble, sel2=lo nibble

        array_push(_list, ["sei", 0, _id]);

        // Fill screen RAM ($scr..$scr+03E7) with (col1<<4)|col2  → 1000 bytes
        array_push(_list, ["lda_imm", _scr_val,               _id]);
        array_push(_list, ["ldx_imm", 0x00,                   _id]);
        array_push(_list, ["label",   _pfx + "scrfill"]);
        array_push(_list, ["sta_abx", _scr_ram,               _id]);
        array_push(_list, ["sta_abx", _scr_ram + 0x100,       _id]);
        array_push(_list, ["sta_abx", _scr_ram + 0x200,       _id]);
        array_push(_list, ["sta_abx", _scr_ram + 0x2E8,       _id]); // covers up to +03E7
        array_push(_list, ["inx",     0,                      _id]);
        array_push(_list, ["bne",     _pfx + "scrfill",       _id]);

        // Fill colour RAM ($D800..$DBE7) with col3  → 1000 bytes
        array_push(_list, ["lda_imm", _vb_col3,               _id]);
        array_push(_list, ["ldx_imm", 0x00,                   _id]);
        array_push(_list, ["label",   _pfx + "colfill"]);
        array_push(_list, ["sta_abx", 0xD800,                 _id]);
        array_push(_list, ["sta_abx", 0xD900,                 _id]);
        array_push(_list, ["sta_abx", 0xDA00,                 _id]);
        array_push(_list, ["sta_abx", 0xDAE8,                 _id]); // covers up to $DBE7
        array_push(_list, ["inx",     0,                      _id]);
        array_push(_list, ["bne",     _pfx + "colfill",       _id]);

        // $D021 = bg
        array_push(_list, ["lda_imm", _vb_bg,                 _id]);
        array_push(_list, ["sta_abs", 0xD021,                 _id]);

        // ── Self-contained VIC setup: bank 1, bitmap $4000, screen $6000, MC on. ──
        // VIC bank 1 = $4000-$7FFF. $DD00 low 2 bits = %10 (inverted: bank 1).
        array_push(_list, ["lda_abs", 0xDD00,                 _id]);
        array_push(_list, ["and_imm", 0xFC,                   _id]);
        array_push(_list, ["ora_imm", 0x02,                   _id]);
        array_push(_list, ["sta_abs", 0xDD00,                 _id]);
        // $D018: screen at $6000 (offset $2000 in bank -> bits 7-4 = %1000),
        //        bitmap at $4000 (offset $0000 in bank -> bit 3 = 0). = $80.
        array_push(_list, ["lda_imm", 0x80,                   _id]);
        array_push(_list, ["sta_abs", 0xD018,                 _id]);
        // $D011: bitmap mode on (BMM=1), display on (DEN=1), rows=25. = $3B.
        array_push(_list, ["lda_imm", 0x3B,                   _id]);
        array_push(_list, ["sta_abs", 0xD011,                 _id]);
        // $D016: multicolour on (MCM=1), 40 cols. = $18.
        array_push(_list, ["lda_imm", 0x18,                   _id]);
        array_push(_list, ["sta_abs", 0xD016,                 _id]);
        array_push(_list, ["lda_imm", _bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xF9,                    _id]);
        array_push(_list, ["lda_imm", (_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFA,                    _id]);                  
        // Screen-RAM base into $DB/$DC (runtime recolour SRAM opcode reads it).
        array_push(_list, ["lda_imm", _scr_ram & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xDB,                   _id]);
        array_push(_list, ["lda_imm", (_scr_ram >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xDC,                   _id]);

        // Store fill-stack base in $E1/$E2 (used by vbmp_fill flood stack).
        array_push(_list, ["lda_imm", _fill_stack & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xE1,                      _id]);
        array_push(_list, ["lda_imm", (_fill_stack >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xE2,                      _id]);
        // Dither: pattern ($D0) and colB ($D2) now come explicitly from each
        // FILL command's stream bytes — no run-count heuristic needed.
        array_push(_list, ["lda_lab_lo", _lbl_stream, _id]);
        array_push(_list, ["sta_zp",     0xFB,        _id]);
        array_push(_list, ["lda_lab_hi", _lbl_stream, _id]);
        array_push(_list, ["sta_zp",     0xFC,        _id]);
        array_push(_list, ["jsr",        "vbmp_render", _id]);
        array_push(_list, ["cli", 0, _id]);
    }

    // ════════════════════════════════════════════════════════════════
    // OFF-SPINE: emit this node's command stream as bytes.
    // org -2 saves spine PC, jump to stream addr; org -3 restores it.
    // _id = noone so Pass 1.5 does NOT count these bytes into node size.
    // STAGE 1: only SETCOL / PLOT / END are translated.
    // ════════════════════════════════════════════════════════════════
    // Stream sits at fill-stack base + $0800 so one node field drives both
    // regions (fill stack = base..base+$07FF, stream = base+$0800). Falls back
    // to asset meta stream_addr only if fill_stack somehow unset.
    // ── Asset-keyed label root: every node referencing this asset derives the
    //    SAME label, so a MACRO_VECTOR_PAGE node elsewhere on the spine can
    //    target vbmp_<asset>_p<N>_stream without knowing which node emitted it.
    var _asset_key = scr_vbmp_label_key(_asset_name);

    // Resolve the page list. Page 0 is emitted at the SETCOL-derived stream
    // label (_lbl_stream) for the setup node's own render, AND under the
    // asset-keyed page-0 label so PAGE nodes can flip back to it. Pages 1..N
    // are packed immediately after — the assembler assigns each its address;
    // no fixed per-page spacing is needed (streams are read-only + resident).
    var _vb_pages = (variable_struct_exists(_vm, "pages") && is_array(_vm.pages) && array_length(_vm.pages) > 0)
        ? _vm.pages
        : [ { commands: _commands, bg: 0, col1: 1, col2: 2, col3: 3 } ];

    var _stream_addr = _fill_stack + 0x0800;
    array_push(_list, ["org", -2]);
    array_push(_list, ["org", _stream_addr]);
    var _vb_id_save = _id;
    _id = noone; // suppress node tagging on stream data

    show_debug_message("VBMP STREAMS: asset '" + _asset_name + "' key='" + _asset_key + "' pages=" + string(array_length(_vb_pages)) + " base_stream_addr=$" + decimal_to_hex(_stream_addr));

    for (var _pg = 0; _pg < array_length(_vb_pages); _pg++) {
        var _pg_struct = _vb_pages[_pg];
        var _pg_cmds = (is_struct(_pg_struct) && variable_struct_exists(_pg_struct, "commands") && is_array(_pg_struct.commands))
            ? _pg_struct.commands : [];

        // Page 0 carries BOTH labels; pages 1..N carry only the asset-keyed one.
        if (_pg == 0) array_push(_list, ["label", _lbl_stream]);
        array_push(_list, ["label", _asset_key + "_p" + string(_pg) + "_stream"]);

    for (var _ci = 0; _ci < array_length(_pg_cmds); _ci++) {
        var _cmd = _pg_cmds[_ci];
        if (!is_struct(_cmd) || !variable_struct_exists(_cmd, "op")) continue;
        var _op = string(_cmd.op);
        switch (_op) {
            case "setcol": {
                var _sc = variable_struct_exists(_cmd, "col") ? (real(_cmd.col) & 0x03) : 0;
                array_push(_list, ["byte", 0x0A]);
                array_push(_list, ["byte", _sc]);
            } break;
            case "plot": {
                var _px = variable_struct_exists(_cmd, "x") ? (real(_cmd.x) & 0x1FF) : 0;
                var _py = variable_struct_exists(_cmd, "y") ? (real(_cmd.y) & 0xFF)  : 0;
                array_push(_list, ["byte", 0x01]);
                array_push(_list, ["byte", _px & 0xFF]);
                array_push(_list, ["byte", (_px >> 8) & 0x01]);
                array_push(_list, ["byte", _py & 0xFF]);
            } break;

            // ── STAGE 2: shapes rasterised to PLOT runs at compile time. ──
            // Each generator returns [x,y] points; we emit an $01 PLOT per point.
            // MC snap: force even X (double-wide pixels) to match the editor.
            case "ellipse": {
                // Native $05: cx cy rx ry (all bytes, X<=255 window mode).
                var _ecx = clamp(real(_cmd.cx), 0, 255);
                var _ecy = clamp(real(_cmd.cy), 0, 199);
                var _erx = clamp(real(_cmd.rx), 1, 127);
                var _ery = clamp(real(_cmd.ry), 1, 127);
                if (_vb_mode == 1) _ecx = (_ecx div 2) * 2; // MC even-X snap on centre
                array_push(_list, ["byte", 0x05]);
                array_push(_list, ["byte", _ecx & 0xFF]);
                array_push(_list, ["byte", _ecy & 0xFF]);
                array_push(_list, ["byte", _erx & 0xFF]);
                array_push(_list, ["byte", _ery & 0xFF]);
            } break;

            case "ellipsefill": {
            // Native $06: cx cy rx ry (all bytes, X<=255 window mode).
            var _fcx = clamp(real(_cmd.cx), 0, 255);
            var _fcy = clamp(real(_cmd.cy), 0, 199);
            var _frx = clamp(real(_cmd.rx), 1, 127);
            var _fry = clamp(real(_cmd.ry), 1, 127);
            if (_vb_mode == 1) _fcx = (_fcx div 2) * 2; // MC even-X snap
            array_push(_list, ["byte", 0x06]);
            array_push(_list, ["byte", _fcx & 0xFF]);
            array_push(_list, ["byte", _fcy & 0xFF]);
            array_push(_list, ["byte", _frx & 0xFF]);
            array_push(_list, ["byte", _fry & 0xFF]);
        } break;

        case "line":
        case "rect":
        case "rectfill": {
            // Native runtime opcodes: $02 line, $03 rect, $04 rectfill.
            // 5 bytes each (opcode + x0 y0 x1 y1) regardless of shape size —
            // the 6502 runtime rasterises, so no per-pixel PLOT expansion.
            // Single-byte coords (X window 0..255). MC even-X snap on X0/X1.
            var _lx0 = clamp(real(_cmd.x0), 0, 255);
            var _ly0 = clamp(real(_cmd.y0), 0, 199);
            var _lx1 = clamp(real(_cmd.x1), 0, 255);
            var _ly1 = clamp(real(_cmd.y1), 0, 199);
            if (_vb_mode == 1) {
                _lx0 = (_lx0 div 2) * 2;
                _lx1 = (_lx1 div 2) * 2;
            }
            var _lop = 0x02;
            if (_op == "rect") {
                _lop = 0x03;
            } else if (_op == "rectfill") {
                _lop = 0x04;
            }
            array_push(_list, ["byte", _lop]);
            array_push(_list, ["byte", _lx0 & 0xFF]);
            array_push(_list, ["byte", _ly0 & 0xFF]);
            array_push(_list, ["byte", _lx1 & 0xFF]);
            array_push(_list, ["byte", _ly1 & 0xFF]);
        } break;

            case "fill": {
                // Native $07: cx cy pattern colB (seed + dither). Flood matches
                // the seed colour, fills with colA (active selector) / colB by
                // the dither pattern. pattern: 0 solid, 1 checker, 2 interlace.
                var _flx = clamp(real(_cmd.x), 0, 255);
                var _fly = clamp(real(_cmd.y), 0, 199);
                if (_vb_mode == 1) _flx = (_flx div 2) * 2; // MC even-X snap
                var _fpat = variable_struct_exists(_cmd, "pattern") ? (real(_cmd.pattern) & 0x03) : 0;
                var _fcolb = variable_struct_exists(_cmd, "colb") ? (real(_cmd.colb) & 0x03) : 0;
                array_push(_list, ["byte", 0x07]);
                array_push(_list, ["byte", _flx & 0xFF]);
                array_push(_list, ["byte", _fly & 0xFF]);
                array_push(_list, ["byte", _fpat]);
                array_push(_list, ["byte", _fcolb]);
            } break;

            // ── RECOLOUR OVERRIDES — colour/screen RAM cell rewrites. ──
            // Not vector opcodes: the runtime pokes RAM so a cell's pairs
            // re-map. 6 bytes each: opcode + col row w h colval.
            //   $08 CRAM → colval = col3 nibble (colour RAM)
            //   $09 SRAM → colval = (col1<<4)|col2 (screen RAM)
            case "recolor_cram": {
                var _rcc = clamp(variable_struct_exists(_cmd, "col") ? real(_cmd.col) : 0, 0, 39);
                var _rcr = clamp(variable_struct_exists(_cmd, "row") ? real(_cmd.row) : 0, 0, 24);
                var _rcw = clamp(variable_struct_exists(_cmd, "w")   ? real(_cmd.w)   : 1, 1, 40);
                var _rch = clamp(variable_struct_exists(_cmd, "h")   ? real(_cmd.h)   : 1, 1, 25);
                if (_rcc + _rcw > 40) _rcw = 40 - _rcc;
                if (_rcr + _rch > 25) _rch = 25 - _rcr;
                var _rc3 = (variable_struct_exists(_cmd, "c3") ? real(_cmd.c3) : 0) & 0x0F;
                array_push(_list, ["byte", 0x08]);
                array_push(_list, ["byte", _rcc & 0xFF]);
                array_push(_list, ["byte", _rcr & 0xFF]);
                array_push(_list, ["byte", _rcw & 0xFF]);
                array_push(_list, ["byte", _rch & 0xFF]);
                array_push(_list, ["byte", _rc3 & 0xFF]);
            } break;

            case "recolor_sram": {
                var _rsc = clamp(variable_struct_exists(_cmd, "col") ? real(_cmd.col) : 0, 0, 39);
                var _rsr = clamp(variable_struct_exists(_cmd, "row") ? real(_cmd.row) : 0, 0, 24);
                var _rsw = clamp(variable_struct_exists(_cmd, "w")   ? real(_cmd.w)   : 1, 1, 40);
                var _rsh = clamp(variable_struct_exists(_cmd, "h")   ? real(_cmd.h)   : 1, 1, 25);
                if (_rsc + _rsw > 40) _rsw = 40 - _rsc;
                if (_rsr + _rsh > 25) _rsh = 25 - _rsr;
                var _rs1 = (variable_struct_exists(_cmd, "c1") ? real(_cmd.c1) : 1) & 0x0F;
                var _rs2 = (variable_struct_exists(_cmd, "c2") ? real(_cmd.c2) : 2) & 0x0F;
                var _rsv = ((_rs1 << 4) | _rs2) & 0xFF;
                array_push(_list, ["byte", 0x09]);
                array_push(_list, ["byte", _rsc & 0xFF]);
                array_push(_list, ["byte", _rsr & 0xFF]);
                array_push(_list, ["byte", _rsw & 0xFF]);
                array_push(_list, ["byte", _rsh & 0xFF]);
                array_push(_list, ["byte", _rsv & 0xFF]);
            } break;
			
			// COPYREGION — duplicate a w×h cell block (bitmap + screen +
            // colour RAM) from source cell to dest cell. 7 bytes:
            //   $0B sc sr dc dr w h
            // Cell-aligned; runtime does the three-plane copy. Clamped so
            // neither source nor dest block runs off the 40×25 grid.
            case "copyregion": {
                var _qsc = clamp(variable_struct_exists(_cmd, "sc") ? real(_cmd.sc) : 0, 0, 39);
                var _qsr = clamp(variable_struct_exists(_cmd, "sr") ? real(_cmd.sr) : 0, 0, 24);
                var _qdc = clamp(variable_struct_exists(_cmd, "dc") ? real(_cmd.dc) : 0, 0, 39);
                var _qdr = clamp(variable_struct_exists(_cmd, "dr") ? real(_cmd.dr) : 0, 0, 24);
                var _qw  = clamp(variable_struct_exists(_cmd, "w")  ? real(_cmd.w)  : 1, 1, 40);
                var _qh  = clamp(variable_struct_exists(_cmd, "h")  ? real(_cmd.h)  : 1, 1, 25);
                // Dest must stay inside the DRAWABLE WINDOW (cols 8..31, rows
                // 5..19); source stays on the grid. Clamp the dest origin into
                // the window first, then trim w/h so neither block overruns.
                if (_qdc < 8) _qdc = 8;
                if (_qdr < 5) _qdr = 5;
                if (_qdc + _qw > 32) _qw = 32 - _qdc;
                if (_qdr + _qh > 20) _qh = 20 - _qdr;
                if (_qsc + _qw > 40) _qw = 40 - _qsc;
                if (_qsr + _qh > 25) _qh = 25 - _qsr;
                array_push(_list, ["byte", 0x0B]);
                array_push(_list, ["byte", _qsc & 0xFF]);
                array_push(_list, ["byte", _qsr & 0xFF]);
                array_push(_list, ["byte", _qdc & 0xFF]);
                array_push(_list, ["byte", _qdr & 0xFF]);
                array_push(_list, ["byte", _qw  & 0xFF]);
                array_push(_list, ["byte", _qh  & 0xFF]);
            } break;

            default: break;
        }
        } // end command loop for this page
        array_push(_list, ["byte", 0x00]); // END — terminates this page's stream
    } // end per-page loop

    // ── VAR-DRIVEN LUTs (only when a var-driven PAGE node targets this asset) ──
    // Emitted INSIDE the stream org block so the assembler packs them
    // immediately after the last page's END byte — no fixed offset needed
    // (same approach as MACRO_METAMAP's VAR data block). strlo/strhi
    // reference the per-page stream labels emitted just above.
    if (_vp_needs_dispatch) {
        var _disp_key = _asset_key;
        var _disp_np  = array_length(_vb_pages);

        array_push(_list, ["label", _disp_key + "_disp_scrval"]);
        for (var _dp = 0; _dp < _disp_np; _dp++) {
            var _dps = _vb_pages[_dp];
            var _dc1 = (is_struct(_dps) && variable_struct_exists(_dps, "col1")) ? (real(_dps.col1) & 0x0F) : 1;
            var _dc2 = (is_struct(_dps) && variable_struct_exists(_dps, "col2")) ? (real(_dps.col2) & 0x0F) : 2;
            array_push(_list, ["byte", ((_dc1 << 4) | _dc2) & 0xFF]);
        }
        array_push(_list, ["label", _disp_key + "_disp_col3"]);
        for (var _dp = 0; _dp < _disp_np; _dp++) {
            var _dps = _vb_pages[_dp];
            var _dc3 = (is_struct(_dps) && variable_struct_exists(_dps, "col3")) ? (real(_dps.col3) & 0x0F) : 3;
            array_push(_list, ["byte", _dc3 & 0xFF]);
        }
        array_push(_list, ["label", _disp_key + "_disp_bg"]);
        for (var _dp = 0; _dp < _disp_np; _dp++) {
            var _dps = _vb_pages[_dp];
            var _dbg = (is_struct(_dps) && variable_struct_exists(_dps, "bg")) ? (real(_dps.bg) & 0x0F) : 0;
            array_push(_list, ["byte", _dbg & 0xFF]);
        }
        array_push(_list, ["label", _disp_key + "_disp_strlo"]);
        for (var _dp = 0; _dp < _disp_np; _dp++) {
            array_push(_list, ["byte_lab_lo", _disp_key + "_p" + string(_dp) + "_stream"]);
        }
        array_push(_list, ["label", _disp_key + "_disp_strhi"]);
        for (var _dp = 0; _dp < _disp_np; _dp++) {
            array_push(_list, ["byte_lab_hi", _disp_key + "_p" + string(_dp) + "_stream"]);
        }
    }

    array_push(_list, ["org", -3]); // restore spine PC
    _id = _vb_id_save;

    // ════════════════════════════════════════════════════════════════
    // VAR-DRIVEN DISPATCH ROUTINE — emitted ONLY when a var-driven PAGE
    // node targets this asset. One routine per asset. Entry X = page index
    // (from the game var). Mirrors the LITERAL MACRO_VECTOR_PAGE flip, but
    // every per-page value is read from a LUT (emitted above) indexed by X
    // instead of baked as an immediate.
    //   Routine label: vbmp_<key>_dispatch
    //   ZP: $D3 = saved page index (X reloaded per fill loop, which uses X
    //       as the 0..255 byte counter). $D4 = held fill value. $F9/$FA
    //       reloaded with bmp_base. $FB/$FC = stream ptr.
    //   Lives inline on the spine, jumped over so it only runs when a PAGE
    //   node JSRs it. Tagged _id so Pass 1.5 (scr_c64_do_update_addresses)
    //   counts it into node size.
    // ════════════════════════════════════════════════════════════════
    if (_vp_needs_dispatch) {
        var _disp_key   = _asset_key;
        var _disp_lbl   = "vbmp_" + _disp_key + "_dispatch";
        var _disp_skip  = _disp_key + "_disp_rtskip";
        var _disp_pfx   = "vbmpd_" + _disp_key + "_";
        var _disp_scr_ram = variable_struct_exists(_vm, "screen_ram") ? real(_vm.screen_ram) : 0x6000;

        array_push(_list, ["jmp_abs", _disp_skip, _id]);
        array_push(_list, ["label",   _disp_lbl]);

        // Save page index (X) — fill loops below clobber X as a counter.
        array_push(_list, ["stx_zp", 0xD3, _id]);

        // Mask interrupts for the whole clear+render. The SID play IRQ uses
        // ZP scratch that overlaps the render pointer ($FB/$FC) and bitmap
        // base ($F9/$FA); if it fires mid-walk it corrupts the stream pointer
        // and vbmp_render hits a stray $00 and returns early (2-3 commands
        // then stop). The setup node and the LITERAL PAGE node both bracket
        // their render in SEI/CLI for the same reason — the dispatcher must
        // too, since it's reached by a bare JSR from the PAGE node.
        array_push(_list, ["sei", 0, _id]);

        // Reload bmp_base into $F9/$FA (vbmp_clear + vbmp_render read it).
        array_push(_list, ["lda_imm", _bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xF9,                    _id]);
        array_push(_list, ["lda_imm", (_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFA,                    _id]);

        // Wipe the bitmap.
        array_push(_list, ["jsr", "vbmp_clear", _id]);

        // ── Fill screen RAM with LUT scrval[page] → 1000 bytes ──
        // Hold scrval in $D4 (X = page), then fill with X as 0..255 counter.
        array_push(_list, ["ldx_zp",  0xD3,                    _id]);
        array_push(_list, ["lda_abx", _disp_key + "_disp_scrval", _id]);
        array_push(_list, ["sta_zp",  0xD4,                    _id]);
        array_push(_list, ["lda_zp",  0xD4,                    _id]);
        array_push(_list, ["ldx_imm", 0x00,                    _id]);
        array_push(_list, ["label",   _disp_pfx + "scrfill"]);
        array_push(_list, ["sta_abx", _disp_scr_ram,           _id]);
        array_push(_list, ["sta_abx", _disp_scr_ram + 0x100,   _id]);
        array_push(_list, ["sta_abx", _disp_scr_ram + 0x200,   _id]);
        array_push(_list, ["sta_abx", _disp_scr_ram + 0x2E8,   _id]);
        array_push(_list, ["inx",     0,                       _id]);
        array_push(_list, ["bne",     _disp_pfx + "scrfill",   _id]);

        // ── Fill colour RAM with LUT col3[page] → 1000 bytes ──
        array_push(_list, ["ldx_zp",  0xD3,                    _id]);
        array_push(_list, ["lda_abx", _disp_key + "_disp_col3", _id]);
        array_push(_list, ["sta_zp",  0xD4,                    _id]);
        array_push(_list, ["lda_zp",  0xD4,                    _id]);
        array_push(_list, ["ldx_imm", 0x00,                    _id]);
        array_push(_list, ["label",   _disp_pfx + "colfill"]);
        array_push(_list, ["sta_abx", 0xD800,                  _id]);
        array_push(_list, ["sta_abx", 0xD900,                  _id]);
        array_push(_list, ["sta_abx", 0xDA00,                  _id]);
        array_push(_list, ["sta_abx", 0xDAE8,                  _id]);
        array_push(_list, ["inx",     0,                       _id]);
        array_push(_list, ["bne",     _disp_pfx + "colfill",   _id]);

        // ── $D021 = LUT bg[page] ──
        array_push(_list, ["ldx_zp",  0xD3,                    _id]);
        array_push(_list, ["lda_abx", _disp_key + "_disp_bg",  _id]);
        array_push(_list, ["sta_abs", 0xD021,                  _id]);

        // ── Screen-RAM base into $DB/$DC (runtime recolour SRAM opcode) ──
        array_push(_list, ["lda_imm", _disp_scr_ram & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xDB,                        _id]);
        array_push(_list, ["lda_imm", (_disp_scr_ram >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xDC,                        _id]);

        // ── Point $FB/$FC at LUT stream ptr[page] + render ──
        array_push(_list, ["ldx_zp",  0xD3,                    _id]);
        array_push(_list, ["lda_abx", _disp_key + "_disp_strlo", _id]);
        array_push(_list, ["sta_zp",  0xFB,                    _id]);
        array_push(_list, ["lda_abx", _disp_key + "_disp_strhi", _id]);
        array_push(_list, ["sta_zp",  0xFC,                    _id]);
        array_push(_list, ["jsr",     "vbmp_render",           _id]);

        array_push(_list, ["cli", 0, _id]);
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _disp_skip]);
    }

} break;

	
// --------------------------------------------------------
// MACRO_SID_SONG — plays a SOUND_EDITOR song on 3 SID voices.
//
// instructions[0]: ["macro_sid_song", asset_name, auto_init, zp_base]
//
// MULTI-SONG. Every song's order rows are concatenated into one set of order
// tables; a song is a [start, end) slice recorded in four per-song header
// tables (songstart/songend/songloop/songflag). _S_ORD is a single absolute
// index into the concatenated tables, so the per-voice trigger path is
// identical to the single-song version — only the end-of-song wrap changed,
// from compile-time immediates to ZP bytes resolved once at init/seek.
//
// ENTRY POINTS:
//   <key>_init   A = song index. Banks BASIC out, sets $D418, then seeks to
//                that song's first order row. Call once.
//   <key>_seek   A = song index, X = order row within that song. Silences all
//                three voices and clears their instrument state. Does not
//                touch $01 or $D418, so it's safe mid-tune.
//   <key>_play   Call once per frame. No arguments.
//
// Emitted inline from the asset's meta — no SE_PAT_*/SE_INS_* BYTE_DATA
// assets exist, so there is nothing to reference. Tables sit on the spine,
// jumped over, and are TAGGED with _id so Pass 1.5 counts them into
// total_node_size: that keeps the memory bar and the conflict detector
// honest about the node's real footprint without a bespoke bar case.
//
// BANKING: init writes $36 to $01, banking BASIC ROM out permanently and
// leaving the KERNAL in (so $0314/$0315 IRQ chaining still works). That
// frees $03-$8F for the player's 28 bytes of state.
//
// NOT $A0-$BA, as an earlier version of this comment claimed: $A0-$A2 is the
// KERNAL jiffy clock, rewritten by the $EA31 IRQ tail on every frame, and
// $90-$FF is KERNAL tape/serial scratch. A player based there has its
// instrument pointer zeroed between steps — the note triggers, the first
// command runs, then the stepper reads ($0000),Y, matches no opcode, and
// falls through to END. Symptom: one attack transient per note, no arp.
// A project that later wants BASIC back can write $37 itself.
//
// Sentinels in a pattern row's note byte:
//   $FF = REST  — gate off; the instrument keeps stepping through its tail
//   $FE = HOLD  — row does nothing, whatever is ringing keeps ringing
//   0-95 = note index into the shared chromatic table
// Instrument byte $FF = none (note plays on the voice's current settings).
// --------------------------------------------------------
case "MACRO_SID_SONG": {
    var _id         = _curr;
    var _i0         = _curr.instructions[0];
    var _asset_name = (array_length(_i0) > 1) ? string(_i0[1]) : "";
    var _auto_init  = (array_length(_i0) > 2 && is_real(_i0[2])) ? real(_i0[2]) : 1;
    var _zp         = (array_length(_i0) > 3 && is_real(_i0[3])) ? (real(_i0[3]) & 0xFF) : 0x03;
    // HARD RESTART — frames of forced gate-off + dummy ADSR before a note's
    // real trigger. 0 = off (trigger immediately, as before). The real 6581/8580
    // delays the attack if the gate is set while the envelope counter sits at
    // certain values; parking the counter in a known state for a couple of
    // frames first makes every attack land on time. Costs a uniform N-frame
    // delay on every note, which shifts the whole song equally.
    var _hr         = (array_length(_i0) > 4 && is_real(_i0[4])) ? clamp(real(_i0[4]), 0, 8) : 2;

    // Which physical SID this instance targets: 0 = $D400 (default, matches
    // every existing song untouched), 1 = $D420, 2 = $D440, 3 = $D460 — the
    // common $20-spacing convention for stacked/Ultimate multi-SID setups.
    // Two independent MACRO_SID_SONG nodes, each on its own chip and its
    // own ZP base (see _zp above — give them at least 44 bytes apart),
    // play fully independently with no shared state at all.
    var _chip       = (array_length(_i0) > 5 && is_real(_i0[5])) ? clamp(real(_i0[5]), 0, 3) : 0;
    var _chip_base  = 0xD400 + (_chip * 0x20);

    show_debug_message("SID_SONG ZP: raw=[" + string(_i0[3]) + "] is_real=" + string(is_real(_i0[3]))
        + " resolved=$" + string_upper(decimal_to_hex(_zp)) + " S_PTR=$" + string_upper(decimal_to_hex(_zp + 25))
        + " chip=" + string(_chip) + " base=$" + string_upper(decimal_to_hex(_chip_base)));

    // ── Resolve the SOUND_EDITOR asset ──
    var _se = noone;
    if (_asset_name != "" && instance_exists(obj_asset_manager)) {
        var _am_ss = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am_ss.asset_list); _ai++) {
            var _a = ds_list_find_value(_am_ss.asset_list, _ai);
            if (_a.type == "MUSIC_MAKER" && _a.name == _asset_name) {
                _se = _a;
                break;
            }
        }
    }
    if (_se == noone) {
        show_debug_message("MACRO_SID_SONG: asset '" + _asset_name + "' not found — skipping");
        break;
    }

    var _sm = _se.meta;

    var _instruments = (variable_struct_exists(_sm, "instruments") && is_array(_sm.instruments)) ? _sm.instruments : [];
    var _patterns    = (variable_struct_exists(_sm, "patterns")    && is_array(_sm.patterns))    ? _sm.patterns    : [];
    var _play_speed  = (variable_struct_exists(_sm, "play_speed")  && is_real(_sm.play_speed))   ? real(_sm.play_speed) : 6;

    // ── SONGS ── every song's order rows are CONCATENATED into one set of
    // order tables. _S_ORD stays a single absolute index into them, so the
    // per-voice trigger code is unchanged; a song is just a [start, end)
    // slice, resolved once at init/seek rather than looked up per row.
    //
    // A pre-songs[] asset that has never been opened in the editor still has
    // only the bare song_order — fold it into a single song here so the
    // build doesn't depend on the user having opened the editor first.
    var _songs = [];
    if (variable_struct_exists(_sm, "songs") && is_array(_sm.songs) && array_length(_sm.songs) > 0) {
        _songs = _sm.songs;
    } else {
        var _legacy_order = (variable_struct_exists(_sm, "song_order") && is_array(_sm.song_order)) ? _sm.song_order : [];
        var _legacy_loop = true;
        if (variable_struct_exists(_sm, "song_loop")) {
            _legacy_loop = _sm.song_loop;
        }
        var _legacy_loop_row = 0;
        if (variable_struct_exists(_sm, "song_loop_row")) {
            _legacy_loop_row = real(_sm.song_loop_row);
        }
        _songs = [ { name: "SONG 00", order: _legacy_order, loop: _legacy_loop, loop_row: _legacy_loop_row } ];
    }

    // Flatten: one order row list, plus per-song start/end/loop/flags.
    // Rows are clipped at 255 total because _S_ORD is one byte.
    var _song_order  = [];   // concatenated rows, in song order
    var _song_start  = [];   // first order-table index of song n
    var _song_end    = [];   // one past the last index of song n
    var _song_lp     = [];   // absolute order index to wrap back to
    var _song_fl     = [];   // bit 0 = loop on
    var _n_songs     = 0;

    for (var _si = 0; _si < array_length(_songs); _si++) {
        var _s_ent = _songs[_si];
        var _s_ord = [];
        if (variable_struct_exists(_s_ent, "order") && is_array(_s_ent.order)) {
            _s_ord = _s_ent.order;
        }
        if (array_length(_s_ord) == 0) {
            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' song " + string(_si)
                + " has no order rows — skipped (not emitted, later songs shift down by one index).");
            continue;
        }
        if (array_length(_song_order) >= 255) {
            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' order rows exceed 255 across all"
                + " songs; song " + string(_si) + " onward is dropped.");
            break;
        }

        var _s_start = array_length(_song_order);
        for (var _sri = 0; _sri < array_length(_s_ord); _sri++) {
            if (array_length(_song_order) >= 255) {
                show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' song " + string(_si)
                    + " truncated at 255 total order rows.");
                break;
            }
            array_push(_song_order, _s_ord[_sri]);
        }
        var _s_end = array_length(_song_order);

        var _s_loop = true;
        if (variable_struct_exists(_s_ent, "loop")) {
            _s_loop = _s_ent.loop;
        }
        var _s_loop_row = 0;
        if (variable_struct_exists(_s_ent, "loop_row")) {
            _s_loop_row = real(_s_ent.loop_row);
        }
        // loop_row is stored per-song (0-based within the song); the runtime
        // needs an absolute index into the concatenated table.
        _s_loop_row = clamp(_s_loop_row, 0, (_s_end - _s_start) - 1);

        array_push(_song_start, _s_start & 0xFF);
        array_push(_song_end,   _s_end   & 0xFF);
        array_push(_song_lp,   (_s_start + _s_loop_row) & 0xFF);
        array_push(_song_fl,   (_s_loop == true) ? 1 : 0);
        _n_songs += 1;
    }

    if (_n_songs > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_songs)
            + " songs; only the first 255 are addressable — the rest are dropped.");
        _n_songs = 255;
        array_resize(_song_start, 255);
        array_resize(_song_end,   255);
        array_resize(_song_lp,    255);
        array_resize(_song_fl,    255);
    }

    var _n_instr = array_length(_instruments);
    var _n_pat   = array_length(_patterns);
    var _n_ord   = array_length(_song_order);

    if (_n_pat == 0 || _n_ord == 0 || _n_songs == 0) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has no patterns, no order rows or no songs — skipping");
        break;
    }
    if (_n_instr > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_instr)
            + " instruments; only the first 255 are addressable — the rest are dropped.");
        _n_instr = 255;
    }
    if (_n_pat > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_pat)
            + " patterns; only the first 255 are addressable — the rest are dropped.");
        _n_pat = 255;
    }
    if (_n_ord > 255) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has " + string(_n_ord)
            + " order rows; only the first 255 are addressable — the rest are dropped.");
        _n_ord = 255;
    }

    _play_speed = clamp(_play_speed, 1, 255);

    show_debug_message("SID_SONG: play_speed=" + string(_play_speed)
        + " n_songs=" + string(_n_songs) + " n_ord=" + string(_n_ord)
        + " n_pat=" + string(_n_pat));

    // Label prefix comes from stable_uid, NOT real(_id) — instance IDs are
    // reallocated on every load, so a JSR stored in another node would point at
    // a label that no longer exists after a save/reload cycle. stable_uid is
    // allocated once in Create and persisted by the workspace serialiser.
    var _key = "sng" + string(_id.stable_uid) + "_";

    // ── ZP MAP — 7 bytes per voice, then 11 shared, then 3 HR bytes per
    //    voice, then 1 control-shadow byte per voice. 44 total. ──
    //   +0/+1  instrument stream pointer (walks the command stream)
    //   +2/+3  instrument stream BASE (fixed at trigger; $03 LOOP adds its
    //          absolute offset to this, since the walking pointer is by then
    //          somewhere in the middle of the stream)
    //   +4     hold counter — frames left on the current D
    //   +5     base note index — the row's note, before instrument offsets
    //   +6     active flag: 0 = idle, 1 = stepping an instrument
    var _V0 = _zp;
    var _V1 = _zp + 7;
    var _V2 = _zp + 14;
    var _S_ORD  = _zp + 21;   // current order row
    var _S_ROW  = _zp + 22;   // master row within the current order row
    var _S_TICK = _zp + 23;   // frames left before the next row advance
    var _S_TMP  = _zp + 24;   // scratch
    var _S_PTR  = _zp + 25;   // pattern-row pointer (2 bytes: +25/+26)
    var _S_LEN  = _zp + 27;   // table-length scratch — see the wrap logic for why
    // ── PER-SONG STATE ── resolved once at init/seek, then read by the wrap
    // logic instead of the compile-time immediates a single-song player used.
    var _S_SONG = _zp + 28;   // current song index
    var _S_END  = _zp + 29;   // one past this song's last order row (absolute)
    var _S_LOOP = _zp + 30;   // order row to wrap back to (absolute)
    var _S_FLAG = _zp + 31;   // bit 0 = loop on
    // ── PER-VOICE HARD-RESTART STATE ── 3 bytes each:
    //   +0  pending note index   (valid while the countdown is running)
    //   +1  pending instrument index
    //   +2  countdown, frames until the real trigger; 0 = idle
    var _H0 = _zp + 32;
    var _H1 = _zp + 35;
    var _H2 = _zp + 38;
    var _h_base = [_H0, _H1, _H2];
    // ── PER-VOICE CONTROL-BYTE SHADOW ── one byte each.
    //
    // SID registers are WRITE-ONLY: reading $D404 returns whatever was last on
    // the data bus, commonly another voice's control byte. So the player can
    // never read back a voice's own waveform. Anywhere it needs to change the
    // gate bit while preserving the waveform — or vice versa — it works from
    // this shadow instead and writes the whole byte.
    var _C0 = _zp + 41;
    var _C1 = _zp + 42;
    var _C2 = _zp + 43;
    var _c_base = [_C0, _C1, _C2];
    var _v_base = [_V0, _V1, _V2];

    // 44 bytes, contiguous. The KERNAL stays banked in (init writes $36, not
    // $35, so $0314/$0315 IRQ chaining keeps working), which rules out two
    // regions entirely:
    //   $A0-$A2  jiffy clock — the $EA31 IRQ tail writes it EVERY frame, so a
    //            pointer parked here is silently zeroed between instrument
    //            steps and the stepper falls through to END on every note.
    //   $90-$FF  KERNAL tape/serial/screen scratch.
    // With BASIC banked out, $03-$8F is free, so the block must start at $03
    // and end no later than $8F.
    var _zp_max = 0x8F - 43;
    if (_zp < 0x03 || _zp > _zp_max) {
        show_debug_message("MACRO_SID_SONG: ZP base $" + string_upper(decimal_to_hex(_zp))
            + " puts the 44-byte block outside the free $03-$8F window (KERNAL owns"
            + " $90-$FF and rewrites the $A0-$A2 jiffy clock every frame); using $03.");
        _zp = 0x03;
        _V0 = _zp;
        _V1 = _zp + 7;
        _V2 = _zp + 14;
        _S_ORD  = _zp + 21;
        _S_ROW  = _zp + 22;
        _S_TICK = _zp + 23;
        _S_TMP  = _zp + 24;
        _S_PTR  = _zp + 25;
        _S_LEN  = _zp + 27;
        _S_SONG = _zp + 28;
        _S_END  = _zp + 29;
        _S_LOOP = _zp + 30;
        _S_FLAG = _zp + 31;
        _H0 = _zp + 32;
        _H1 = _zp + 35;
        _H2 = _zp + 38;
        _h_base = [_H0, _H1, _H2];
        _C0 = _zp + 41;
        _C1 = _zp + 42;
        _C2 = _zp + 43;
        _c_base = [_C0, _C1, _C2];
        _v_base = [_V0, _V1, _V2];
    }

    // ════════════════════════════════════════════════════════════════
    // SHARED NOTE TABLE — 96 entries, emitted once per build.
    // Built via scr_note_name_to_freq so this and MACRO_SID_SOUND resolve
    // the same note name to the same 16-bit register value.
    // ════════════════════════════════════════════════════════════════
    if (!variable_global_exists("sidsong_notetab_emitted") || global.sidsong_notetab_emitted == false) {
        global.sidsong_notetab_emitted = true;

        var _nt_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        var _nt_freq  = array_create(96, 0);
        for (var _nti = 0; _nti < 96; _nti++) {
            var _nt_oct  = _nti div 12;
            var _nt_step = _nti mod 12;
            var _nt_f    = scr_note_name_to_freq(_nt_names[_nt_step] + string(_nt_oct));
            if (_nt_f < 0) {
                _nt_f = 0;
            }
            _nt_freq[_nti] = _nt_f;
        }

        array_push(_list, ["jmp_abs", "SIDSONG_NT_SKIP", _id]);
        array_push(_list, ["label",   "SIDSONG_NOTELO"]);
        for (var _nti = 0; _nti < 96; _nti++) {
            array_push(_list, ["byte", _nt_freq[_nti] & 0xFF, _id]);
        }
        array_push(_list, ["label",   "SIDSONG_NOTEHI"]);
        for (var _nti = 0; _nti < 96; _nti++) {
            array_push(_list, ["byte", (_nt_freq[_nti] >> 8) & 0xFF, _id]);
        }
        array_push(_list, ["label",   "SIDSONG_NT_SKIP"]);
    }

    // ════════════════════════════════════════════════════════════════
    // DATA BLOCK — instruments, patterns, order tables. On the spine,
    // jumped over, tagged _id so Pass 1.5 sizes them onto this node.
    // ════════════════════════════════════════════════════════════════
    var _lbl_dskip = _key + "dskip";
    array_push(_list, ["jmp_abs", _lbl_dskip, _id]);

    // ── 1. INSTRUMENT BLOBS ──
    // 4 header bytes (AD, SR, PW lo, PW hi) then the compiled command stream.
    // Re-parsed here rather than trusting instr.compiled, which is an
    // editor-side cache that may predate the last text edit.
    for (var _ii = 0; _ii < _n_instr; _ii++) {
        var _ins = _instruments[_ii];

        var _atk = 0;
        var _dec = 8;
        var _sus = 8;
        var _rel = 0;
        if (variable_struct_exists(_ins, "attack"))  _atk = clamp(real(_ins.attack),  0, 15);
        if (variable_struct_exists(_ins, "decay"))   _dec = clamp(real(_ins.decay),   0, 15);
        if (variable_struct_exists(_ins, "sustain")) _sus = clamp(real(_ins.sustain), 0, 15);
        if (variable_struct_exists(_ins, "release")) _rel = clamp(real(_ins.release), 0, 15);

        var _ins_pw = 0x0800;
        if (variable_struct_exists(_ins, "pulse_width")) {
            _ins_pw = real(_ins.pulse_width) & 0x0FFF;
        }

        var _ins_txt = "";
        if (variable_struct_exists(_ins, "text")) {
            _ins_txt = string(_ins.text);
        }
        var _ins_comp = scr_instrument_parse(_ins_txt);

        for (var _ei = 0; _ei < array_length(_ins_comp.errors); _ei++) {
            show_debug_message("MACRO_SID_SONG: instrument " + string(_ii) + " — " + string(_ins_comp.errors[_ei]));
        }

        var _dbg_b = "";
        for (var _dbi = 0; _dbi < array_length(_ins_comp.bytes); _dbi++) {
            _dbg_b += string_upper(decimal_to_hex(_ins_comp.bytes[_dbi])) + " ";
        }
        show_debug_message("INSTR " + string(_ii) + " TEXT=[" + _ins_txt + "]");
        show_debug_message("INSTR " + string(_ii) + " BYTES=" + _dbg_b
            + " (count=" + string(array_length(_ins_comp.bytes)) + ")");

        array_push(_list, ["label", _key + "ins" + string(_ii)]);
        array_push(_list, ["byte", ((_atk << 4) | _dec) & 0xFF, _id]);   // AD
        array_push(_list, ["byte", ((_sus << 4) | _rel) & 0xFF, _id]);   // SR
        array_push(_list, ["byte", _ins_pw & 0xFF,              _id]);
        array_push(_list, ["byte", (_ins_pw >> 8) & 0x0F,       _id]);
        for (var _bi = 0; _bi < array_length(_ins_comp.bytes); _bi++) {
            array_push(_list, ["byte", _ins_comp.bytes[_bi] & 0xFF, _id]);
        }
    }

    // ── 2. INSTRUMENT POINTER TABLE ──
    // Always at least one entry, so a song with no instruments still has a
    // table the runtime can index without a special case.
    array_push(_list, ["label", _key + "inslo"]);
    if (_n_instr == 0) {
        array_push(_list, ["byte", 0x00, _id]);
    }
    for (var _ii = 0; _ii < _n_instr; _ii++) {
            array_push(_list, ["byte_lab_lo", _key + "ins" + string(_ii), _id]);
        }
    array_push(_list, ["label", _key + "inshi"]);
    if (_n_instr == 0) {
        array_push(_list, ["byte", 0x00, _id]);
    }
    for (var _ii = 0; _ii < _n_instr; _ii++) {
            array_push(_list, ["byte_lab_hi", _key + "ins" + string(_ii), _id]);
        }

    // ── 3. PATTERN BLOBS ── 2 bytes per row: note index, instrument index.
    for (var _pi = 0; _pi < _n_pat; _pi++) {
        var _pat     = _patterns[_pi];
        var _pat_len = 64;
        if (variable_struct_exists(_pat, "pattern_len")) {
            _pat_len = clamp(real(_pat.pattern_len), 1, 255);
        }
        var _pat_steps = [];
        if (variable_struct_exists(_pat, "steps") && is_array(_pat.steps)) {
            _pat_steps = _pat.steps;
        }

        array_push(_list, ["label", _key + "pat" + string(_pi)]);

        for (var _ri = 0; _ri < _pat_len; _ri++) {
            var _note_byte  = 0xFE;   // default: empty / hold
            var _instr_byte = 0xFF;   // default: no instrument

            if (_ri < array_length(_pat_steps)) {
                var _st = _pat_steps[_ri];

                var _st_empty = true;
                if (variable_struct_exists(_st, "empty")) {
                    _st_empty = _st.empty;
                }
                var _st_note = "";
                if (variable_struct_exists(_st, "note")) {
                    _st_note = string(_st.note);
                }
                var _st_instr = -1;
                if (variable_struct_exists(_st, "instr_idx")) {
                    _st_instr = real(_st.instr_idx);
                }

                if (_st_empty == true) {
                    _note_byte = 0xFE;
                } else if (_st_note == "" || _st_note == "---") {
                    _note_byte = 0xFF;
                } else {
                    // Resolve the note name to a chromatic index. Both parsers
                    // use midi = 12*(oct+1)+base, so index = midi - 12 puts
                    // C-0 at 0 and B-7 at 95. Anything the parser rejects is
                    // warned about by name rather than silently going quiet.
                    var _st_idx = scr_sid_song_note_index(_st_note);
                    if (_st_idx < 0) {
                        show_debug_message("MACRO_SID_SONG: pattern " + string(_pi) + " row " + string(_ri)
                            + " — unrecognised note '" + _st_note + "', emitted as a rest.");
                        _note_byte = 0xFF;
                    } else {
                        _note_byte = _st_idx;
                    }
                }

                if (_st_instr >= 0 && _st_instr < _n_instr) {
                    _instr_byte = _st_instr;
                }
            }

            array_push(_list, ["byte", _note_byte  & 0xFF, _id]);
            array_push(_list, ["byte", _instr_byte & 0xFF, _id]);
        }
    }

    // ── 4. PATTERN POINTER + LENGTH TABLES ──
    array_push(_list, ["label", _key + "patlo"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
            array_push(_list, ["byte_lab_lo", _key + "pat" + string(_pi), _id]);
        }
    array_push(_list, ["label", _key + "pathi"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
            array_push(_list, ["byte_lab_hi", _key + "pat" + string(_pi), _id]);
        }
    array_push(_list, ["label", _key + "patlen"]);
    for (var _pi = 0; _pi < _n_pat; _pi++) {
        var _pl = 64;
        if (variable_struct_exists(_patterns[_pi], "pattern_len")) {
            _pl = clamp(real(_patterns[_pi].pattern_len), 1, 255);
        }
        array_push(_list, ["byte", _pl & 0xFF, _id]);
    }

    // ── 5. ORDER TABLES ──
    // repeat_short / force_len are flattened here: the runtime reads a plain
    // per-row target length and a per-row wrap flag. force_len is a HARD
    // length when set (it overrides, it is not a minimum) — matching
    // _se_row_target_len in the editor exactly.
    var _ord_v  = [[], [], []];
    var _ord_ln = [];
    var _ord_wr = [];

    for (var _oi = 0; _oi < _n_ord; _oi++) {
        var _orow  = _song_order[_oi];
        var _ovals = [-1, -1, -1];
        if (variable_struct_exists(_orow, "v1")) _ovals[0] = real(_orow.v1);
        if (variable_struct_exists(_orow, "v2")) _ovals[1] = real(_orow.v2);
        if (variable_struct_exists(_orow, "v3")) _ovals[2] = real(_orow.v3);

        var _o_target = 0;
        for (var _vi = 0; _vi < 3; _vi++) {
            var _pv = _ovals[_vi];
            if (_pv >= 0 && _pv < _n_pat) {
                array_push(_ord_v[_vi], _pv & 0xFF);
                var _pv_len = 64;
                if (variable_struct_exists(_patterns[_pv], "pattern_len")) {
                    _pv_len = clamp(real(_patterns[_pv].pattern_len), 1, 255);
                }
                if (_pv_len > _o_target) {
                    _o_target = _pv_len;
                }
            } else {
                array_push(_ord_v[_vi], 0xFF);
            }
        }

        var _o_force = 0;
        if (variable_struct_exists(_orow, "force_len")) {
            _o_force = real(_orow.force_len);
        }
        if (_o_force > 0) {
            _o_target = _o_force;
        }
        if (_o_target <= 0) {
            _o_target = 64;
        }
        array_push(_ord_ln, clamp(_o_target, 1, 255) & 0xFF);

        var _o_wrap = 0;
        if (variable_struct_exists(_orow, "repeat_short")) {
            if (_orow.repeat_short == true) {
                _o_wrap = 1;
            }
        }
        array_push(_ord_wr, _o_wrap);
    }

    var _ord_lbls = [_key + "ordv1", _key + "ordv2", _key + "ordv3"];
    for (var _vi = 0; _vi < 3; _vi++) {
        array_push(_list, ["label", _ord_lbls[_vi]]);
        for (var _oi = 0; _oi < _n_ord; _oi++) {
            array_push(_list, ["byte", _ord_v[_vi][_oi], _id]);
        }
    }
    array_push(_list, ["label", _key + "ordlen"]);
    for (var _oi = 0; _oi < _n_ord; _oi++) {
        array_push(_list, ["byte", _ord_ln[_oi], _id]);
    }
    array_push(_list, ["label", _key + "ordwrap"]);
    for (var _oi = 0; _oi < _n_ord; _oi++) {
        array_push(_list, ["byte", _ord_wr[_oi], _id]);
    }

    // ── 6. PER-SONG HEADER TABLES ──
    // Indexed by song number. init/seek copy the three relevant bytes into ZP
    // once, so the row-advance path costs the same as it did single-song.
    array_push(_list, ["label", _key + "songend"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_end[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songloop"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_lp[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songflag"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_fl[_sgi2], _id]);
    }
    array_push(_list, ["label", _key + "songstart"]);
    for (var _sgi2 = 0; _sgi2 < _n_songs; _sgi2++) {
        array_push(_list, ["byte", _song_start[_sgi2], _id]);
    }

    array_push(_list, ["label", _lbl_dskip]);

    // ════════════════════════════════════════════════════════════════
    // RUNTIME — <key>_init and <key>_play, both RTS.
    // Jumped over so nothing runs by falling through.
    // ════════════════════════════════════════════════════════════════
    var _L_skip   = _key + "rtskip";
    var _L_init   = _key + "init";
    var _L_seek   = _key + "seek";
    var _L_play   = _key + "play";
    var _L_rowadv = _key + "rowadv";
    var _L_instrs = _key + "instrs";

    array_push(_list, ["jmp_abs", _L_skip, _id]);

    // ── INIT ── A = song index (clamped), X ignored.
    // Banks BASIC out, sets full volume, then falls into SEEK with X = 0 so
    // the song starts at its own first order row.
    array_push(_list, ["label",   _L_init]);
    // Bank BASIC out, KERNAL stays in ($0314/$0315 IRQ chaining still works).
    // This is what frees $03-$8F for the player's state.
    array_push(_list, ["pha",     0,      _id]);
    array_push(_list, ["lda_imm", 0x36,   _id]);
    array_push(_list, ["sta_zp",  0x01,   _id]);
    array_push(_list, ["lda_imm", 0x0F,   _id]);
    array_push(_list, ["sta_abs", _chip_base + 0x18, _id]);   // full volume, filter off
    array_push(_list, ["pla",     0,      _id]);
    array_push(_list, ["ldx_imm", 0x00,   _id]);   // start at the song's first row
    array_push(_list, ["jmp_abs", _L_seek, _id]);

    // ── SEEK ── A = song index, X = order row WITHIN that song (0 = start).
    // Does not touch $01 or $D418, so it's safe to call mid-tune from any
    // banking configuration the project has since set up.
    //
    // Voices are silenced and their instrument state cleared on every seek:
    // without it you drop into the new position with whatever was ringing
    // still ringing and each voice part-way through its old instrument —
    // the same class of stale-state bug as the loop-wrap fix.
    array_push(_list, ["label",   _L_seek]);

    // Clamp the song index. An out-of-range song would index past the header
    // tables into whatever data follows and set _S_END to garbage.
    array_push(_list, ["cmp_imm", _n_songs & 0xFF, _id]);
    array_push(_list, ["bcc",     _key + "skok",   _id]);
    array_push(_list, ["lda_imm", 0x00,            _id]);
    array_push(_list, ["label",   _key + "skok"]);
    array_push(_list, ["sta_zp",  _S_SONG, _id]);
    array_push(_list, ["stx_zp",  _S_TMP,  _id]);   // stash the requested row

    // Resolve this song's slice into ZP.
    array_push(_list, ["tax",     0,       _id]);   // X = song index
    array_push(_list, ["lda_abx", _key + "songend",  _id]);
    array_push(_list, ["sta_zp",  _S_END,  _id]);
    array_push(_list, ["lda_abx", _key + "songloop", _id]);
    array_push(_list, ["sta_zp",  _S_LOOP, _id]);
    array_push(_list, ["lda_abx", _key + "songflag", _id]);
    array_push(_list, ["sta_zp",  _S_FLAG, _id]);

    // Absolute order row = this song's start + the requested offset, clamped
    // to the song's own last row so a bad offset can't run into the next song.
    array_push(_list, ["lda_abx", _key + "songstart", _id]);
    array_push(_list, ["clc",     0,       _id]);
    array_push(_list, ["adc_zp",  _S_TMP,  _id]);
    array_push(_list, ["cmp_zp",  _S_END,  _id]);
    array_push(_list, ["bcc",     _key + "skrow",    _id]);
    array_push(_list, ["lda_zp",  _S_END,  _id]);
    array_push(_list, ["sec",     0,       _id]);
    array_push(_list, ["sbc_imm", 0x01,    _id]);
    array_push(_list, ["label",   _key + "skrow"]);
    array_push(_list, ["sta_zp",  _S_ORD,  _id]);

    array_push(_list, ["lda_imm", 0x00,    _id]);
    array_push(_list, ["sta_zp",  _S_ROW,  _id]);
    array_push(_list, ["lda_imm", 0x01,    _id]);
    array_push(_list, ["sta_zp",  _S_TICK, _id]);   // 1 = the next play call lands on the row
    for (var _vi = 0; _vi < 3; _vi++) {
        var _vb = _v_base[_vi];
        array_push(_list, ["lda_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 4, _id]);   // hold = 0
        array_push(_list, ["sta_zp",  _vb + 6, _id]);   // inactive
        array_push(_list, ["sta_abs", _chip_base + 0x04 + (_vi * 7), _id]);   // silence: gate off, no waveform
        // A seek mid-countdown would otherwise fire the old song's pending
        // note N frames into the new position.
        array_push(_list, ["sta_zp",  _h_base[_vi] + 2, _id]);   // countdown = idle
        array_push(_list, ["sta_zp",  _c_base[_vi],     _id]);   // shadow matches the register
    }
    array_push(_list, ["rts",     0,      _id]);

    // ── PLAY ──
    array_push(_list, ["label",   _L_play]);
    array_push(_list, ["dec_zp",  _S_TICK,   _id]);
    array_push(_list, ["beq",     _L_rowadv, _id]);
    array_push(_list, ["jmp_abs", _L_instrs, _id]);

    array_push(_list, ["label",   _L_rowadv]);
    array_push(_list, ["lda_imm", _play_speed & 0xFF, _id]);
    array_push(_list, ["sta_zp",  _S_TICK, _id]);

    // Trigger each voice's row. Unrolled per voice — three copies beats the
    // ZP juggling a shared subroutine would need to index a voice's block.
    for (var _vi = 0; _vi < 3; _vi++) {
        var _vb      = _v_base[_vi];
        var _hb      = _h_base[_vi];
        var _cb      = _c_base[_vi];
        var _vp      = _key + "v" + string(_vi) + "_";
        var _L_vskip = _vp + "skip";
        var _D400    = _chip_base + (_vi * 7);

        // X = this voice's pattern index for the current order row.
        array_push(_list, ["ldx_zp",  _S_ORD,         _id]);
        array_push(_list, ["lda_abx", _ord_lbls[_vi], _id]);
        array_push(_list, ["cmp_imm", 0xFF,           _id]);
        array_push(_list, ["bne",     _vp + "havepat", _id]);
        array_push(_list, ["jmp_abs", _L_vskip,       _id]);   // no pattern this voice
        array_push(_list, ["label",   _vp + "havepat"]);
        array_push(_list, ["tax",     0,              _id]);   // X = pattern idx

        // Local row: master row, wrapped or stopped by this order row's flag.
        // Patterns are short, so a repeated subtract beats a divide.
        //
        // NOTE: the assembler resolves label operands for lda_abx but NOT for
        // cmp_abx / sbc_abx, so this pattern's length is fetched once with
        // lda_abx into a ZP scratch byte and every compare/subtract works
        // against that copy. X is preserved throughout (it holds the pattern
        // index and nothing here reloads it).
        array_push(_list, ["lda_abx", _key + "patlen", _id]);
        array_push(_list, ["sta_zp",  _S_LEN,          _id]);   // $S_LEN = this pattern's length

        array_push(_list, ["lda_zp",  _S_ROW,          _id]);
        array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
        array_push(_list, ["bcc",     _vp + "rowok",   _id]);   // row < len, use as-is
        array_push(_list, ["ldy_zp",  _S_ORD,          _id]);
        array_push(_list, ["sta_zp",  _S_TMP,          _id]);
        array_push(_list, ["lda_aby", _key + "ordwrap", _id]);
        array_push(_list, ["bne",     _vp + "dowrap",  _id]);
        array_push(_list, ["jmp_abs", _L_vskip,        _id]);   // NRs: silent past its own end
        array_push(_list, ["label",   _vp + "dowrap"]);
        array_push(_list, ["lda_zp",  _S_TMP,          _id]);
        array_push(_list, ["label",   _vp + "wraplp"]);
        array_push(_list, ["sec",     0,               _id]);
        array_push(_list, ["sbc_zp",  _S_LEN,          _id]);
        array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
        array_push(_list, ["bcs",     _vp + "wraplp",  _id]);
        array_push(_list, ["label",   _vp + "rowok"]);
        array_push(_list, ["sta_zp",  _S_TMP,          _id]);   // $S_TMP = local row

        // Row pointer = pattern base + local_row * 2.
        array_push(_list, ["lda_abx", _key + "patlo", _id]);
        array_push(_list, ["sta_zp",  _S_PTR,         _id]);
        array_push(_list, ["lda_abx", _key + "pathi", _id]);
        array_push(_list, ["sta_zp",  _S_PTR + 1,     _id]);
        array_push(_list, ["lda_zp",  _S_TMP,         _id]);
        array_push(_list, ["asl_a",   0,              _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["adc_zp",  _S_PTR,         _id]);
        array_push(_list, ["sta_zp",  _S_PTR,         _id]);
        array_push(_list, ["lda_zp",  _S_PTR + 1,     _id]);
        array_push(_list, ["adc_imm", 0x00,           _id]);
        array_push(_list, ["sta_zp",  _S_PTR + 1,     _id]);

        // Note byte.
        array_push(_list, ["ldy_imm", 0x00,   _id]);
        array_push(_list, ["lda_izy", _S_PTR, _id]);

        // $FE = hold — leave the voice entirely alone.
        array_push(_list, ["cmp_imm", 0xFE,            _id]);
        array_push(_list, ["bne",     _vp + "nothold", _id]);
        array_push(_list, ["jmp_abs", _L_vskip,        _id]);
        array_push(_list, ["label",   _vp + "nothold"]);

        // $FF = rest — gate off AND stop the instrument.
        //
        // An earlier version left the instrument stepping so its tail could
        // carry on modulating. That reads well for a one-shot whose stream
        // runs to $04 END on its own, but it does nothing for a LOOPING
        // instrument: the loop never reaches END, so the voice stays active
        // forever, cycling its stream silently and never releasing. A rest
        // that can't stop a voice isn't a rest, so this now clears the
        // active flag too — matching what a tracker's --- is expected to do.
        array_push(_list, ["cmp_imm", 0xFF,            _id]);
        array_push(_list, ["bne",     _vp + "isnote",  _id]);
        // Gate off from the SHADOW, not a read of $D404 — the register is
        // write-only and reads back bus noise. Waveform bits are PRESERVED so
        // the release tail still has an oscillator; only bit 0 clears.
        array_push(_list, ["lda_zp",  _cb,             _id]);
        array_push(_list, ["and_imm", 0xFE,            _id]);
        array_push(_list, ["sta_zp",  _cb,             _id]);
        array_push(_list, ["sta_abs", _D400 + 4,       _id]);
        array_push(_list, ["lda_imm", 0x00,            _id]);
        array_push(_list, ["sta_zp",  _vb + 6,         _id]);   // instrument off
        array_push(_list, ["sta_zp",  _hb + 2,         _id]);   // cancel any pending note
        array_push(_list, ["jmp_abs", _L_vskip,        _id]);
        array_push(_list, ["label",   _vp + "isnote"]);

        // Real note: stash the base index, then read the instrument byte.
        array_push(_list, ["sta_zp",  _vb + 5, _id]);
        array_push(_list, ["ldy_imm", 0x01,    _id]);
        array_push(_list, ["lda_izy", _S_PTR,  _id]);

        if (_hr > 0) {
            // ── HARD RESTART, PHASE 1 ──
            // Don't sound the note now. Stash it, gate the voice off, and load
            // the dummy ADSR so the envelope counter is driven to a known
            // state. The stepper counts down and runs the real trigger (phase
            // 2) _hr frames from now.
            //
            // Note and instrument both go to the pending bytes: the row
            // pointer will have moved on by the time phase 2 runs, so nothing
            // can be re-read from the pattern then.
            array_push(_list, ["sta_zp",  _hb + 1, _id]);   // pending instrument
            array_push(_list, ["lda_zp",  _vb + 5, _id]);
            array_push(_list, ["sta_zp",  _hb + 0, _id]);   // pending note
            array_push(_list, ["lda_imm", _hr & 0xFF, _id]);
            array_push(_list, ["sta_zp",  _hb + 2, _id]);   // start the countdown

            // Silence and park the envelope. Clearing the active flag stops
            // the stepper walking the OLD instrument through the window —
            // without it the previous note keeps modulating over the restart.
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _D400 + 4, _id]);   // gate off, no waveform
            array_push(_list, ["sta_zp",  _cb,       _id]);   // shadow matches
            array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // instrument idle
            array_push(_list, ["lda_imm", 0x0F,      _id]);
            array_push(_list, ["sta_abs", _D400 + 5, _id]);   // dummy AD
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_abs", _D400 + 6, _id]);   // dummy SR
            array_push(_list, ["jmp_abs", _L_vskip,  _id]);
        }

        if (_hr == 0) {

        array_push(_list, ["cmp_imm", 0xFF,           _id]);
        array_push(_list, ["bne",     _vp + "hasins", _id]);

        // No instrument: write the frequency and gate on with a plain pulse,
        // leaving AD/SR as whatever the voice last had.
        array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _D400 + 0,        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _D400 + 1,        _id]);
        array_push(_list, ["lda_imm", 0x41,             _id]);   // pulse + gate
        array_push(_list, ["sta_abs", _D400 + 4,        _id]);
        array_push(_list, ["sta_zp",  _cb,              _id]);
        array_push(_list, ["lda_imm", 0x00,             _id]);
        array_push(_list, ["sta_zp",  _vb + 6,          _id]);   // no instrument to step
        array_push(_list, ["jmp_abs", _L_vskip,         _id]);
        array_push(_list, ["label",   _vp + "hasins"]);

        // Instrument: point the voice at its blob, write AD/SR/PW, gate on.
        array_push(_list, ["tax",     0,              _id]);   // X = instrument idx
        array_push(_list, ["lda_abx", _key + "inslo", _id]);
        array_push(_list, ["sta_zp",  _vb + 0,        _id]);
        array_push(_list, ["sta_zp",  _vb + 2,        _id]);   // stream base (for $03 LOOP)
        array_push(_list, ["lda_abx", _key + "inshi", _id]);
        array_push(_list, ["sta_zp",  _vb + 1,        _id]);
        array_push(_list, ["sta_zp",  _vb + 3,        _id]);

        // Header: +0 AD, +1 SR, +2 PW lo, +3 PW hi
        array_push(_list, ["ldy_imm", 0x00,      _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 5, _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 6, _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 2, _id]);
        array_push(_list, ["iny",     0,         _id]);
        array_push(_list, ["lda_izy", _vb + 0,   _id]);
        array_push(_list, ["sta_abs", _D400 + 3, _id]);

        // Frequency from the base note.
        array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _D400 + 0,        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _D400 + 1,        _id]);

        // Walking pointer moves past the 4 header bytes; the BASE stays put,
        // because $03 LOOP targets are offsets from the start of the command
        // stream, not from the blob.
        array_push(_list, ["clc",     0,       _id]);
        array_push(_list, ["lda_zp",  _vb + 0, _id]);
        array_push(_list, ["adc_imm", 0x04,    _id]);
        array_push(_list, ["sta_zp",  _vb + 0, _id]);
        array_push(_list, ["lda_zp",  _vb + 1, _id]);
        array_push(_list, ["adc_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 1, _id]);
        // Base points at the stream start too (blob + 4).
        array_push(_list, ["clc",     0,       _id]);
        array_push(_list, ["lda_zp",  _vb + 2, _id]);
        array_push(_list, ["adc_imm", 0x04,    _id]);
        array_push(_list, ["sta_zp",  _vb + 2, _id]);
        array_push(_list, ["lda_zp",  _vb + 3, _id]);
        array_push(_list, ["adc_imm", 0x00,    _id]);
        array_push(_list, ["sta_zp",  _vb + 3, _id]);

        // Gate on with a default pulse; the instrument's first $00 overrides
        // the waveform on this same frame.
        array_push(_list, ["lda_imm", 0x41,      _id]);
        array_push(_list, ["sta_abs", _D400 + 4, _id]);
        array_push(_list, ["sta_zp",  _cb,       _id]);
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_zp",  _vb + 4,   _id]);   // hold = 0, step immediately
        array_push(_list, ["lda_imm", 0x01,      _id]);
        array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // active

        }   // end if (_hr == 0) — with HR on, phase 1 above jumps to _L_vskip
            // and the whole immediate-trigger body is unreachable, so it isn't
            // emitted at all. Phase 2 in the stepper does the equivalent work.

        array_push(_list, ["label",   _L_vskip]);
    }
    // Advance the master row; roll into the next order row at the target.
    // Same label-operand restriction as the pattern length above — fetch via
    // lda_abx into scratch, then compare ZP-to-ZP.
    array_push(_list, ["inc_zp",  _S_ROW, _id]);
    array_push(_list, ["ldx_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_abx", _key + "ordlen", _id]);
    array_push(_list, ["sta_zp",  _S_LEN,          _id]);
    array_push(_list, ["lda_zp",  _S_ROW,          _id]);
    array_push(_list, ["cmp_zp",  _S_LEN,          _id]);
    array_push(_list, ["bcs",     _key + "nextord", _id]);
    array_push(_list, ["jmp_abs", _L_instrs,        _id]);
    array_push(_list, ["label",   _key + "nextord"]);
    array_push(_list, ["lda_imm", 0x00,   _id]);
    array_push(_list, ["sta_zp",  _S_ROW, _id]);
    array_push(_list, ["inc_zp",  _S_ORD, _id]);
    // End-of-song is now the CURRENT song's end, held in ZP, not a compile-time
    // constant — that's the whole of what makes multi-song work at runtime.
    array_push(_list, ["lda_zp",  _S_ORD, _id]);
    array_push(_list, ["cmp_zp",  _S_END, _id]);
    array_push(_list, ["bcc",     _L_instrs, _id]);

    // Past the end. Loop or stop, per this song's flag byte.
    array_push(_list, ["lda_zp",  _S_FLAG,   _id]);
    array_push(_list, ["and_imm", 0x01,      _id]);
    array_push(_list, ["beq",     _key + "songstop", _id]);

    // LOOP — back to this song's loop row. Reset per-voice instrument state
    // on the wrap: without it each voice re-enters still stepping whatever
    // instrument it was part-way through when the pattern ended, with its own
    // leftover hold counter, so the three voices come back in at different
    // points in their streams and drift against each other. Only the second
    // and later loops are affected, which is what makes it look like a timing
    // bug rather than stale state.
    array_push(_list, ["lda_zp",  _S_LOOP, _id]);
    array_push(_list, ["sta_zp",  _S_ORD,  _id]);
    array_push(_list, ["lda_imm", 0x00,    _id]);
    for (var _vi = 0; _vi < 3; _vi++) {
        array_push(_list, ["sta_zp", _v_base[_vi] + 4, _id]);   // hold = 0
        array_push(_list, ["sta_zp", _v_base[_vi] + 6, _id]);   // inactive
        array_push(_list, ["sta_zp", _h_base[_vi] + 2, _id]);   // no pending note
        array_push(_list, ["sta_zp", _c_base[_vi],     _id]);   // shadow matches
    }
    array_push(_list, ["jmp_abs", _L_instrs, _id]);

    // STOP — park on this song's last row, silence everything, go inactive.
    array_push(_list, ["label",   _key + "songstop"]);
    array_push(_list, ["lda_zp",  _S_END, _id]);
    array_push(_list, ["sec",     0,      _id]);
    array_push(_list, ["sbc_imm", 0x01,   _id]);
    array_push(_list, ["sta_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_imm", 0x00,   _id]);
    for (var _vi = 0; _vi < 3; _vi++) {
        array_push(_list, ["sta_abs", _chip_base + 0x04 + (_vi * 7), _id]);
        array_push(_list, ["sta_zp",  _v_base[_vi] + 6,   _id]);
        array_push(_list, ["sta_zp",  _h_base[_vi] + 2,   _id]);
        array_push(_list, ["sta_zp",  _c_base[_vi],       _id]);
    }

    // ── PER-FRAME INSTRUMENT STEPPING ──
    // Runs every call regardless of whether a row advanced, so D-holds are
    // measured in frames and fast arps work between rows.
    array_push(_list, ["label", _L_instrs]);

    for (var _vi = 0; _vi < 3; _vi++) {
        var _vb      = _v_base[_vi];
        var _hb      = _h_base[_vi];
        var _cb      = _c_base[_vi];
        var _ip      = _key + "i" + string(_vi) + "_";
        var _L_idone = _ip + "done";
        var _L_iloop = _ip + "loop";
        var _D400    = _chip_base + (_vi * 7);

        if (_hr > 0) {
            // ── HARD RESTART, PHASE 2 ──
            // Countdown running? Tick it. At zero, sound the pending note for
            // real: the envelope counter has been parked by the dummy ADSR for
            // _hr frames, so the attack starts immediately instead of waiting
            // for the counter to wrap.
            //
            // Runs BEFORE the stepper below and falls through into it, so a
            // note firing this frame gets its first instrument command on the
            // same frame — matching what the non-HR path did.
            array_push(_list, ["lda_zp",  _hb + 2,      _id]);
            array_push(_list, ["bne",     _ip + "hrgo", _id]);
            array_push(_list, ["jmp_abs", _ip + "hrno", _id]);
            array_push(_list, ["label",   _ip + "hrgo"]);
            array_push(_list, ["dec_zp",  _hb + 2,      _id]);
            array_push(_list, ["lda_zp",  _hb + 2,      _id]);
            array_push(_list, ["beq",     _ip + "hrfire", _id]);
            array_push(_list, ["jmp_abs", _L_idone,     _id]);   // still waiting, voice stays silent
            array_push(_list, ["label",   _ip + "hrfire"]);

            // Restore the base note the row asked for, then trigger.
            array_push(_list, ["lda_zp",  _hb + 0, _id]);
            array_push(_list, ["sta_zp",  _vb + 5, _id]);
            array_push(_list, ["lda_zp",  _hb + 1, _id]);
            array_push(_list, ["cmp_imm", 0xFF,           _id]);
            array_push(_list, ["bne",     _ip + "hrins",  _id]);

            // No instrument: frequency + plain pulse gate, AD/SR left as the
            // dummy values — matching the non-HR path's "whatever the voice
            // last had".
            array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
            array_push(_list, ["sta_abs", _D400 + 0,        _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
            array_push(_list, ["sta_abs", _D400 + 1,        _id]);
            array_push(_list, ["lda_imm", 0x41,             _id]);
            array_push(_list, ["sta_abs", _D400 + 4,        _id]);
            array_push(_list, ["sta_zp",  _cb,              _id]);
            array_push(_list, ["lda_imm", 0x00,             _id]);
            array_push(_list, ["sta_zp",  _vb + 6,          _id]);
            array_push(_list, ["jmp_abs", _L_idone,         _id]);
            array_push(_list, ["label",   _ip + "hrins"]);

            // Instrument: same sequence the row trigger uses.
            array_push(_list, ["tax",     0,              _id]);
            array_push(_list, ["lda_abx", _key + "inslo", _id]);
            array_push(_list, ["sta_zp",  _vb + 0,        _id]);
            array_push(_list, ["sta_zp",  _vb + 2,        _id]);
            array_push(_list, ["lda_abx", _key + "inshi", _id]);
            array_push(_list, ["sta_zp",  _vb + 1,        _id]);
            array_push(_list, ["sta_zp",  _vb + 3,        _id]);

            array_push(_list, ["ldy_imm", 0x00,      _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 5, _id]);   // real AD
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 6, _id]);   // real SR
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 2, _id]);
            array_push(_list, ["iny",     0,         _id]);
            array_push(_list, ["lda_izy", _vb + 0,   _id]);
            array_push(_list, ["sta_abs", _D400 + 3, _id]);

            array_push(_list, ["ldx_zp",  _vb + 5,          _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
            array_push(_list, ["sta_abs", _D400 + 0,        _id]);
            array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
            array_push(_list, ["sta_abs", _D400 + 1,        _id]);

            array_push(_list, ["clc",     0,       _id]);
            array_push(_list, ["lda_zp",  _vb + 0, _id]);
            array_push(_list, ["adc_imm", 0x04,    _id]);
            array_push(_list, ["sta_zp",  _vb + 0, _id]);
            array_push(_list, ["lda_zp",  _vb + 1, _id]);
            array_push(_list, ["adc_imm", 0x00,    _id]);
            array_push(_list, ["sta_zp",  _vb + 1, _id]);
            array_push(_list, ["clc",     0,       _id]);
            array_push(_list, ["lda_zp",  _vb + 2, _id]);
            array_push(_list, ["adc_imm", 0x04,    _id]);
            array_push(_list, ["sta_zp",  _vb + 2, _id]);
            array_push(_list, ["lda_zp",  _vb + 3, _id]);
            array_push(_list, ["adc_imm", 0x00,    _id]);
            array_push(_list, ["sta_zp",  _vb + 3, _id]);

            array_push(_list, ["lda_imm", 0x41,      _id]);
            array_push(_list, ["sta_abs", _D400 + 4, _id]);   // gate on
            array_push(_list, ["sta_zp",  _cb,       _id]);
            array_push(_list, ["lda_imm", 0x00,      _id]);
            array_push(_list, ["sta_zp",  _vb + 4,   _id]);   // hold = 0
            array_push(_list, ["lda_imm", 0x01,      _id]);
            array_push(_list, ["sta_zp",  _vb + 6,   _id]);   // active
            // Falls through into the stepper below.
            array_push(_list, ["label",   _ip + "hrno"]);
        }

        // Skip if this voice has no live instrument.
        array_push(_list, ["lda_zp",  _vb + 6,      _id]);
        array_push(_list, ["bne",     _ip + "live", _id]);
        array_push(_list, ["jmp_abs", _L_idone,     _id]);
        array_push(_list, ["label",   _ip + "live"]);

        // Holding? tick down and stop.
        array_push(_list, ["lda_zp",  _vb + 4,      _id]);
        array_push(_list, ["beq",     _ip + "step", _id]);
        array_push(_list, ["dec_zp",  _vb + 4,      _id]);
        array_push(_list, ["jmp_abs", _L_idone,     _id]);
        array_push(_list, ["label",   _ip + "step"]);

        // Execute commands until a HOLD parks us or the stream ends.
        array_push(_list, ["label",   _L_iloop]);
        array_push(_list, ["ldy_imm", 0x00,    _id]);
        array_push(_list, ["lda_izy", _vb + 0, _id]);

        // $00 = WAVE — set the control register with the gate forced ON.
        //
        // This used to read $D404 and OR in the live gate bit. That is wrong on
        // real hardware: SID registers are WRITE-ONLY, and a read returns
        // whatever was last on the data bus — commonly another voice's control
        // byte written moments earlier. So voice 3's "preserve my gate" would
        // pick up voice 2's waveform bits, and since the SID ANDs combined
        // waveforms together rather than mixing them, the voice went thin and
        // quiet for no reason visible in its own instrument. Confirmed on
        // x64sc and on real hardware; x64 hides it because it doesn't model
        // the bus.
        //
        // The gate bit is forced ON rather than preserved: this handler only
        // runs while the voice is actively stepping an instrument ($vb+6 == 1),
        // and that is exactly when the gate is on. $04 END gates off and clears
        // the flag, so the stepper can't reach here with the gate down. The
        // resulting byte is written to the SHADOW as well as the register, so
        // END and the $FF rest can later clear bit 0 while keeping the
        // waveform — giving a release tail with the right timbre.
        array_push(_list, ["cmp_imm", 0x00,       _id]);
        array_push(_list, ["bne",     _ip + "n0", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["ora_imm", 0x01,       _id]);
        array_push(_list, ["sta_zp",  _cb,        _id]);
        array_push(_list, ["sta_abs", _D400 + 4,  _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["lda_zp",  _vb + 0,    _id]);
        array_push(_list, ["adc_imm", 0x02,       _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 1,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_iloop,   _id]);
        array_push(_list, ["label",   _ip + "n0"]);

        // $01 = NOTE — base index + signed offset, clamped to the table.
        // The preview does base_hz * 2^(offset/12), a semitone shift; one
        // table entry per semitone makes that a single ADC here.
        array_push(_list, ["cmp_imm", 0x01,        _id]);
        array_push(_list, ["bne",     _ip + "n1",  _id]);
        array_push(_list, ["ldy_imm", 0x01,        _id]);
        array_push(_list, ["lda_izy", _vb + 0,     _id]);
        array_push(_list, ["clc",     0,           _id]);
        array_push(_list, ["adc_zp",  _vb + 5,     _id]);   // two's complement handles the sign
        array_push(_list, ["cmp_imm", 96,          _id]);
        array_push(_list, ["bcc",     _ip + "nok", _id]);
        array_push(_list, ["lda_imm", 95,          _id]);   // clamp rather than read past the table
        array_push(_list, ["label",   _ip + "nok"]);
        array_push(_list, ["tax",     0,                _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTELO", _id]);
        array_push(_list, ["sta_abs", _D400 + 0,        _id]);
        array_push(_list, ["lda_abx", "SIDSONG_NOTEHI", _id]);
        array_push(_list, ["sta_abs", _D400 + 1,        _id]);
        array_push(_list, ["clc",     0,        _id]);
        array_push(_list, ["lda_zp",  _vb + 0,  _id]);
        array_push(_list, ["adc_imm", 0x02,     _id]);
        array_push(_list, ["sta_zp",  _vb + 0,  _id]);
        array_push(_list, ["lda_zp",  _vb + 1,  _id]);
        array_push(_list, ["adc_imm", 0x00,     _id]);
        array_push(_list, ["sta_zp",  _vb + 1,  _id]);
        array_push(_list, ["jmp_abs", _L_iloop, _id]);
        array_push(_list, ["label",   _ip + "n1"]);

        // $02 = HOLD — park for n frames. n-1, because this frame counts.
        array_push(_list, ["cmp_imm", 0x02,       _id]);
        array_push(_list, ["bne",     _ip + "n2", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["sec",     0,          _id]);
        array_push(_list, ["sbc_imm", 0x01,       _id]);
        array_push(_list, ["sta_zp",  _vb + 4,    _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["lda_zp",  _vb + 0,    _id]);
        array_push(_list, ["adc_imm", 0x02,       _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 1,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_idone,   _id]);
        array_push(_list, ["label",   _ip + "n2"]);

        // $03 = LOOP — the argument is an absolute byte offset from the START
        // of the command stream, so it's added to the stored BASE, not to the
        // walking pointer (which is by now somewhere in the middle).
        array_push(_list, ["cmp_imm", 0x03,       _id]);
        array_push(_list, ["bne",     _ip + "n3", _id]);
        array_push(_list, ["ldy_imm", 0x01,       _id]);
        array_push(_list, ["lda_izy", _vb + 0,    _id]);
        array_push(_list, ["clc",     0,          _id]);
        array_push(_list, ["adc_zp",  _vb + 2,    _id]);
        array_push(_list, ["sta_zp",  _vb + 0,    _id]);
        array_push(_list, ["lda_zp",  _vb + 3,    _id]);
        array_push(_list, ["adc_imm", 0x00,       _id]);
        array_push(_list, ["sta_zp",  _vb + 1,    _id]);
        array_push(_list, ["jmp_abs", _L_iloop,   _id]);
        array_push(_list, ["label",   _ip + "n3"]);

        // $04, or anything unrecognised = END — gate off, mark inactive.
        //
        // Waveform bits are PRESERVED so the release phase still has an
        // oscillator to release; only bit 0 clears. Worked from the shadow
        // because $D404 can't be read back reliably.
        array_push(_list, ["lda_zp",  _cb,       _id]);
        array_push(_list, ["and_imm", 0xFE,      _id]);
        array_push(_list, ["sta_zp",  _cb,       _id]);
        array_push(_list, ["sta_abs", _D400 + 4, _id]);
        array_push(_list, ["lda_imm", 0x00,      _id]);
        array_push(_list, ["sta_zp",  _vb + 6,   _id]);

        array_push(_list, ["label",   _L_idone]);
    }

    array_push(_list, ["rts", 0, _id]);
    array_push(_list, ["label", _L_skip]);

    // Auto-init on the spine so the node is drop-and-go. The user then JSRs
    // <key>_play once per frame from their own loop or IRQ handler.
    if (_auto_init == 1) {
        // A is undefined wherever the node happens to sit on the spine, and
        // _init takes the song index in A — so load 0 explicitly. Drop-and-go
        // always starts the first song.
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["jsr", _L_init, _id]);
    }
} break;	
	
	
	
// --------------------------------------------------------
// MACRO_CODE — freeform assembly text block
// --------------------------------------------------------
case "MACRO_CODE": {
                var _id = _curr;
                var _code_text = string(_curr.instructions[0][1]);
                if (_code_text != "") {
                    var _parsed = scr_parse_asm_text(_code_text);
                    for (var _dbi = 0; _dbi < array_length(_parsed); _dbi++) {
                        show_debug_message("PARSED[" + string(_dbi) + "] = " + string(_parsed[_dbi]));
                    }
                    for (var _pi = 0; _pi < array_length(_parsed); _pi++) {
                        var _inst = _parsed[_pi];
                        if (_inst[0] == "label") {
                            // Labels pass through untagged
                            array_push(_list, _inst);
                        } else if (_inst[0] == "pc") {
                            // .pc / *. / .* → org (untagged, matches assembler format)
                            array_push(_list, ["org", _inst[1]]);
                        } else if (_inst[0] == "byte" && array_length(_inst) > 2) {
                            // .byte v,v,v → expand into individual tagged byte entries
                            for (var _bxi = 1; _bxi < array_length(_inst); _bxi++) {
                                array_push(_list, ["byte", _inst[_bxi], _id]);
                            }
                        } else {
                           if (_inst[0] == "_line_map_" || _inst[0] == "const") continue;
	                        var _tagged = [_inst[0], _inst[1], _id];
	                        if (array_length(_inst) > 2)
	                            array_push(_tagged, _inst[2]);
	                        array_push(_list, _tagged);
                        }
                    }
                }
            } break;

// --------------------------------------------------------
// MACRO_CLEAR_BMP_RECT
// Zeroes a rectangular block of C64 bitmap data, in char-cell units.
// Every bit-pair in the cleared cells becomes %00, which the VIC renders
// as $D021 (background) regardless of what screen or colour RAM hold —
// so this is a true background wipe without touching either palette plane.
//
// Drop it on the spine BEFORE a MACRO_MOVE_BMP_BLOCK to pre-clear the
// region a room's stamps are about to be blitted into: MASK00 blend lets
// the destination show through the source's holes, so without a wipe the
// previous room's pixels survive in the gaps.
//
// Layout: instructions[0] = ["macro_clear_bmp_rect", bmp_addr, col, row, w, h]
//
// The cells of a char row are contiguous in the bitmap (w cells = w*8
// bytes), so each row is one inner Y-loop; the outer X-loop steps char rows
// by adding 320 to the ZP pointer. Same shape as MOVE_BMP_BLOCK's fast path.
//   $FB/$FC = dest pointer
//   $02     = page counter (only when w >= 32, i.e. row span > 255)
// --------------------------------------------------------
case "MACRO_CLEAR_BMP_RECT": {
    var _id       = _curr;
    var _cbr_bmp  = is_real(_curr.instructions[0][1]) ? real(_curr.instructions[0][1]) : 0x4000;
    var _cbr_col  = is_real(_curr.instructions[0][2]) ? clamp(real(_curr.instructions[0][2]), 0, 39) : 0;
    var _cbr_row  = is_real(_curr.instructions[0][3]) ? clamp(real(_curr.instructions[0][3]), 0, 24) : 0;
    var _cbr_w    = is_real(_curr.instructions[0][4]) ? real(_curr.instructions[0][4]) : 40;
    var _cbr_h    = is_real(_curr.instructions[0][5]) ? real(_curr.instructions[0][5]) : 25;

    // Trim the rect to the 40x25 grid so a bad w/h can't walk the pointer
    // off the end of the bitmap and scribble over whatever follows it.
    if (_cbr_w < 1) _cbr_w = 1;
    if (_cbr_h < 1) _cbr_h = 1;
    if (_cbr_col + _cbr_w > 40) _cbr_w = 40 - _cbr_col;
    if (_cbr_row + _cbr_h > 25) _cbr_h = 25 - _cbr_row;

    var _cbr_pfx = "cbr_" + string(real(_id)) + "_";

    // Top-left byte of the rect: base + row*320 + col*8.
    var _cbr_base = _cbr_bmp + (_cbr_row * 320) + (_cbr_col * 8);

    // Bytes per char row of the rect, and how they split across pages.
    var _cbr_span  = _cbr_w * 8;             // 8..320
    var _cbr_pages = _cbr_span div 256;
    var _cbr_rem   = _cbr_span mod 256;

    // A VIC bank 2 bitmap ($8000-$BFFF) sits under BASIC ROM in the CPU's
    // view, so writes would land in ROM shadow rather than RAM. Bank BASIC
    // out for the duration, exactly as MOVE_BMP_BLOCK does.
    var _cbr_basic_off = (_cbr_bmp >= 0x8000 && _cbr_bmp < 0xC000);

    // $FB/$FC is also the SID play routine's scratch — an IRQ landing
    // mid-wipe would corrupt the pointer and scatter zeroes across memory.
    array_push(_list, ["sei", 0, _id]);

    if (_cbr_basic_off) {
        array_push(_list, ["lda_imm", 0x36, _id]); // RAM under BASIC, Kernal + I/O on
        array_push(_list, ["sta_zp",  0x01, _id]);
    }

    array_push(_list, ["lda_imm", _cbr_base & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xFB,                    _id]);
    array_push(_list, ["lda_imm", (_cbr_base >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xFC,                    _id]);

    array_push(_list, ["ldx_imm", _cbr_h,          _id]);   // X = char-row counter
    array_push(_list, ["label",   _cbr_pfx + "row"     ]);

    // Full 256-byte pages first (only when w >= 32), via Y wrap.
    if (_cbr_pages > 0) {
        array_push(_list, ["lda_imm", _cbr_pages,        _id]);
        array_push(_list, ["sta_zp",  0x02,              _id]);
        array_push(_list, ["lda_imm", 0x00,              _id]);
        array_push(_list, ["ldy_imm", 0,                 _id]);
        array_push(_list, ["label",   _cbr_pfx + "pg"        ]);
        array_push(_list, ["sta_izy", 0xFB,              _id]);
        array_push(_list, ["iny",     0,                 _id]);
        array_push(_list, ["bne",     _cbr_pfx + "pg",   _id]);
        array_push(_list, ["inc_zp",  0xFC,              _id]);   // Y wrapped -> next page
        array_push(_list, ["dec_zp",  0x02,              _id]);
        array_push(_list, ["bne",     _cbr_pfx + "pg",   _id]);
    }

    // Remainder bytes. Y is 0 here after a wrap, or fresh if there were no pages.
    if (_cbr_rem > 0) {
        array_push(_list, ["lda_imm", 0x00,              _id]);
        array_push(_list, ["ldy_imm", 0,                 _id]);
        array_push(_list, ["label",   _cbr_pfx + "rm"        ]);
        array_push(_list, ["sta_izy", 0xFB,              _id]);
        array_push(_list, ["iny",     0,                 _id]);
        array_push(_list, ["cpy_imm", _cbr_rem,          _id]);
        array_push(_list, ["bne",     _cbr_pfx + "rm",   _id]);
    }

    // Next char row. The page loop bumped the HI byte _cbr_pages times, so
    // back those out before adding the true 320-byte row stride — otherwise
    // the pointer lands _cbr_pages pages too far down.
    if (_cbr_pages > 0) {
        array_push(_list, ["lda_zp",  0xFC,        _id]);
        array_push(_list, ["sec",     0,           _id]);
        array_push(_list, ["sbc_imm", _cbr_pages,  _id]);
        array_push(_list, ["sta_zp",  0xFC,        _id]);
    }
    array_push(_list, ["clc",     0,    _id]);
    array_push(_list, ["lda_zp",  0xFB, _id]);
    array_push(_list, ["adc_imm", 64,   _id]);   // 320 & $FF
    array_push(_list, ["sta_zp",  0xFB, _id]);
    array_push(_list, ["lda_zp",  0xFC, _id]);
    array_push(_list, ["adc_imm", 1,    _id]);   // 320 >> 8
    array_push(_list, ["sta_zp",  0xFC, _id]);

    array_push(_list, ["dex",     0,                  _id]);
    array_push(_list, ["bne",     _cbr_pfx + "row",   _id]);

    if (_cbr_basic_off) {
        array_push(_list, ["lda_imm", 0x37, _id]);
        array_push(_list, ["sta_zp",  0x01, _id]);
    }

    array_push(_list, ["cli", 0, _id]);
} break;
              
// --------------------------------------------------------
// MACRO_MOVE_BMP_BLOCK
// Copies a rectangular block of C64 bitmap data from one bitmap
// to another (or same), in char-cell units. Optionally also copies
// the colour pair from screen RAM (bitmap+$2000) and colour RAM ($D800).
// X/Y offset UV vars (in cells) are added to source and dest at runtime.
// Self-modifying operands keep each row a single fast LDA/STA pair.
// --------------------------------------------------------
case "MACRO_MOVE_BMP_BLOCK": {
    var _id      = _curr;
    var _src_bmp = is_real(_curr.instructions[0][1])  ? real(_curr.instructions[0][1])  : 0x4000;
    var _dst_bmp = is_real(_curr.instructions[0][2])  ? real(_curr.instructions[0][2])  : 0x4000;
    var _src_x   = is_real(_curr.instructions[0][3])  ? real(_curr.instructions[0][3])  : 0;
    var _src_y   = is_real(_curr.instructions[0][4])  ? real(_curr.instructions[0][4])  : 0;
    var _dst_x   = is_real(_curr.instructions[0][5])  ? real(_curr.instructions[0][5])  : 0;
    var _dst_y   = is_real(_curr.instructions[0][6])  ? real(_curr.instructions[0][6])  : 0;
    var _bw      = is_real(_curr.instructions[0][7])  ? real(_curr.instructions[0][7])  : 1;
    var _bh      = is_real(_curr.instructions[0][8])  ? real(_curr.instructions[0][8])  : 1;
    var _sxv     = string(_curr.instructions[0][9]);
    var _syv     = string(_curr.instructions[0][10]);
    var _dxv     = string(_curr.instructions[0][11]);
    var _dyv     = string(_curr.instructions[0][12]);
    var _col_on  = is_real(_curr.instructions[0][13]) ? real(_curr.instructions[0][13]) : 1;

    // Backfill: workspaces saved before the blend/copy_scr slots existed have
    // 14 entries; before the ASSET slots, 16. Pad to 20 with defaults that
    // reproduce the OLD behaviour (OPAQUE + write screen RAM + LIT mode), so
    // existing projects build unchanged.
    var _had_14 = (array_length(_curr.instructions[0]) == 14);
    var _had_16 = (array_length(_curr.instructions[0]) == 16);

    while (array_length(_curr.instructions[0]) < 19) {
        array_push(_curr.instructions[0], 0);
    }
    if (_had_14) {
        _curr.instructions[0][14] = 1;  // OPAQUE
        _curr.instructions[0][15] = 1;  // write screen RAM
    }
    if (_had_14 || _had_16) {
        _curr.instructions[0][16] = 0;  // LIT mode
        _curr.instructions[0][17] = "";
        _curr.instructions[0][18] = "";
    }

    var _blend    = is_real(_curr.instructions[0][14]) ? real(_curr.instructions[0][14]) : 0;
    var _scr_on   = is_real(_curr.instructions[0][15]) ? real(_curr.instructions[0][15]) : 1;
    var _src_mode = is_real(_curr.instructions[0][16]) ? real(_curr.instructions[0][16]) : 0;
    var _rec_ast  = string(_curr.instructions[0][17]);
    var _entry_v  = string(_curr.instructions[0][18]);

    // ── WRITE COLL backfill ──  Pad to 21 (write_coll=0 = no-op).
    while (array_length(_curr.instructions[0]) < 21) {
        array_push(_curr.instructions[0], (array_length(_curr.instructions[0]) == 19) ? 0 : "");
    }
    if (!is_real(_curr.instructions[0][19])) { _curr.instructions[0][19] = 0; }

    var _wcoll_on = is_real(_curr.instructions[0][19]) ? real(_curr.instructions[0][19]) : 0;
    var _bbt_ast  = string(_curr.instructions[0][20]);

    // Resolve the tag grid's injected base. Missing table quietly disables the
    // write rather than reading $0000.
    var _bbt_base = 0;
    if (_wcoll_on == 1 && _bbt_ast != "" && _bbt_ast != "[clear]") {
        if (instance_exists(obj_asset_manager)) {
            var _am_bbt = obj_asset_manager;
            for (var _bti = 0; _bti < ds_list_size(_am_bbt.asset_list); _bti++) {
                var _bta = ds_list_find_value(_am_bbt.asset_list, _bti);
                if (_bta.type == "BYTE_DATA" && _bta.name == _bbt_ast) {
                    _bbt_base = _bta.address;
                    break;
                }
            }
        }
        if (_bbt_base == 0) {
            show_debug_message("MOVE_BMP_BLOCK: WRITE COLL on but BBT '" + _bbt_ast + "' not found — write skipped");
        }
    }
    // ASSET-mode only: the map is rebuilt by walking the record table, which LIT
    // mode has no concept of. The node greys it out there; this is the backstop.
    var _wcoll_live = (_wcoll_on == 1 && _bbt_base != 0 && _src_mode == 1);
	
    if (_bw < 1) _bw = 1;
    if (_bh < 1) _bh = 1;

    // ── MCMASK00 lookup table — emitted ONCE per build, jumped over. ──
    // MCMASK00[b] = %11 in every 2-bit pair where b's pair is %00, else %00.
    // Used by MASK00 blend to merge a source byte over a destination byte:
    //     lda (src),y / tax / lda MCMASK00,x / and (dst),y / ora (src),y
    // The AND keeps the destination only under the source's holes; the ORA
    // drops in the source's opaque pairs. Tagged _id so Pass 1.5 sizes it
    // onto this node.
    if (_blend == 0) {
        if (!variable_global_exists("bmpblk_mask_emitted") || global.bmpblk_mask_emitted == false) {
            global.bmpblk_mask_emitted = true;
            array_push(_list, ["jmp_abs", "bmpblk_mask_skip", _id]);
            array_push(_list, ["label",   "MCMASK00"]);
            for (var _mi = 0; _mi < 256; _mi++) {
                var _mv = 0;
                for (var _mp = 0; _mp < 4; _mp++) {
                    var _shift = _mp * 2;
                    var _pair  = (_mi >> _shift) & 0x03;
                    if (_pair == 0) {
                        _mv = _mv | (0x03 << _shift);
                    }
                }
                array_push(_list, ["byte", _mv & 0xFF, _id]);
            }
            array_push(_list, ["label", "bmpblk_mask_skip"]);
        }

        // ── MBBTONE: colour -> luma group LUT. 16 bytes, emitted once. ──
        // MASK00 in ASSET mode needs this to remap surviving destination
        // pixels onto the source's palette by tonal rank. See
        // scr_c64_tone_group for why. OPAQUE never reads it.
        if (!variable_global_exists("bmpblk_tone_emitted") || global.bmpblk_tone_emitted == false) {
            global.bmpblk_tone_emitted = true;
            array_push(_list, ["jmp_abs", "bmpblk_tone_skip", _id]);
            array_push(_list, ["label",   "MBBTONE"]);
            for (var _ti = 0; _ti < 16; _ti++) {
                array_push(_list, ["byte", scr_c64_tone_group(_ti), _id]);
            }
            array_push(_list, ["label", "bmpblk_tone_skip"]);
        }

        // ── MBBBIT: pair value -> slot bit. 4 bytes, emitted once. ──
        // MASK00's free-slot scan needs "pair 1/2/3 -> bit 1/2/3" without a
        // shift loop. Index 0 is padding so the table can be indexed by the
        // raw pair value.
        if (!variable_global_exists("bmpblk_bit_emitted") || global.bmpblk_bit_emitted == false) {
            global.bmpblk_bit_emitted = true;
            array_push(_list, ["jmp_abs", "bmpblk_bit_skip", _id]);
            array_push(_list, ["label",   "MBBBIT"]);
            array_push(_list, ["byte", 0x00, _id]);
            array_push(_list, ["byte", 0x02, _id]);
            array_push(_list, ["byte", 0x04, _id]);
            array_push(_list, ["byte", 0x08, _id]);
            array_push(_list, ["label", "bmpblk_bit_skip"]);
        }
    }

    // ── MULTIPLY LUTs for ASSET mode — emitted ONCE per build, jumped over. ──
    // ASSET mode reads cell coords from a record at RUNTIME, so the address
    // maths (base + row*320 + col*8) must happen in 6502 rather than in GML.
    // Doing it with add-loops would cost six multiply loops per record; these
    // tables reduce it to two adds:
    //   MBBR320_LO/HI[r] = r * 320   (r = 0..24)   — bitmap row offset
    //   MBBR40_LO/HI[r]  = r * 40    (r = 0..24)   — screen/colour row offset
    //   MBBCOL8[c]       = c * 8     (c = 0..39)   — bitmap column offset
    // Total 40 + 40 + 40 = 130 bytes. Same pattern as BMPCHARROW_LO/HI.
    if (_src_mode == 1) {
        if (!variable_global_exists("bmpblk_lut_emitted") || global.bmpblk_lut_emitted == false) {
            global.bmpblk_lut_emitted = true;
            array_push(_list, ["jmp_abs", "bmpblk_lut_skip", _id]);

            array_push(_list, ["label", "MBBR320_LO"]);
            for (var _ri = 0; _ri < 25; _ri++) {
                array_push(_list, ["byte", (_ri * 320) & 0xFF, _id]);
            }
            array_push(_list, ["label", "MBBR320_HI"]);
            for (var _ri = 0; _ri < 25; _ri++) {
                array_push(_list, ["byte", ((_ri * 320) >> 8) & 0xFF, _id]);
            }
            array_push(_list, ["label", "MBBR40_LO"]);
            for (var _ri = 0; _ri < 25; _ri++) {
                array_push(_list, ["byte", (_ri * 40) & 0xFF, _id]);
            }
            array_push(_list, ["label", "MBBR40_HI"]);
            for (var _ri = 0; _ri < 25; _ri++) {
                array_push(_list, ["byte", ((_ri * 40) >> 8) & 0xFF, _id]);
            }
            // c * 8 for c = 0..39 reaches 312 — it does NOT fit in one byte.
            // Columns 32-39 overflow, so this needs LO and HI halves like the
            // row tables, or the source pointer lands 256 bytes short.
            array_push(_list, ["label", "MBBCOL8_LO"]);
            for (var _ci = 0; _ci < 40; _ci++) {
                array_push(_list, ["byte", (_ci * 8) & 0xFF, _id]);
            }
            array_push(_list, ["label", "MBBCOL8_HI"]);
            for (var _ci = 0; _ci < 40; _ci++) {
                array_push(_list, ["byte", ((_ci * 8) >> 8) & 0xFF, _id]);
            }

            array_push(_list, ["label", "bmpblk_lut_skip"]);
        }
    }

    // If src or dst sits in VIC bank 2 ($8000-$BFFF), the screen RAM and
    // colour source land in BASIC ROM space ($A000-$BFFF in CPU view).
    // Bank BASIC out for the duration of the copy, restore default at the end.
    var _needs_basic_off = (
        (_src_bmp >= 0x8000 && _src_bmp < 0xC000) ||
        (_dst_bmp >= 0x8000 && _dst_bmp < 0xC000)
    );
    // Mask IRQs for the whole copy. $FB-$FE are the source/dest pointers, and
    // the SID play routine clobbers ZP in that range — an IRQ landing mid-copy
    // would corrupt the pointers and scatter writes across memory. MACRO_MAP
    // brackets its copy for the same reason.
    array_push(_list, ["sei", 0, _id]);

    if (_needs_basic_off) {
        array_push(_list, ["lda_imm", 0x36, _id]); // RAM under BASIC, Kernal + I/O on
        array_push(_list, ["sta_zp",  0x01, _id]);
    }

    // Resolve UV var addresses (0 means "no var assigned")
    var _resolve_var = function(_nm) {
        if (_nm == "") return 0;
        if (ds_map_exists(global.named_loc_map, _nm))
            return ds_map_find_value(global.named_loc_map, _nm);
        return 0;
    };
    var _sxv_addr = _resolve_var(_sxv);
    var _syv_addr = _resolve_var(_syv);
    var _dxv_addr = _resolve_var(_dxv);
    var _dyv_addr = _resolve_var(_dyv);

    var _has_sxv = (_sxv_addr != 0);
    var _has_syv = (_syv_addr != 0);
    var _has_dxv = (_dxv_addr != 0);
    var _has_dyv = (_dyv_addr != 0);

    // Region layout owned by scr_bmp_regions — the SAME helper the asset
    // injector uses, so the addresses this node reads from are guaranteed to
    // be the addresses those bytes were actually written to.
    var _src_r     = scr_bmp_regions(_src_bmp);
    var _src_bank  = _src_r.bank;
    var _src_bbase = _src_r.bank_base;
    var _src_scr   = _src_r.scr_addr;

    var _dst_r     = scr_bmp_regions(_dst_bmp);
    var _dst_bank  = _dst_r.bank;
    var _dst_bbase = _dst_r.bank_base;
    var _dst_scr   = _dst_r.scr_addr;

    var _pfx        = "mbb_" + string(real(_id)) + "_";
    var _lbl_src_lo = _pfx + "srclo";
    var _lbl_src_hi = _pfx + "srchi";
    var _lbl_dst_lo = _pfx + "dstlo";
    var _lbl_dst_hi = _pfx + "dsthi";

    // Compile-time base offsets in bytes:
    //   bitmap byte addr = bmp_base + (y_cell * 320) + (x_cell * 8) + pixel_row
    //   screen addr      = bmp_base + $2000 + (y_cell * 40) + x_cell
    var _src_bmp_base = _src_bmp + (_src_y * 320) + (_src_x * 8);
    var _dst_bmp_base = _dst_bmp + (_dst_y * 320) + (_dst_x * 8);
    var _src_scr_base = _src_scr + (_src_y * 40)  + _src_x;
    var _dst_scr_base = _dst_scr + (_dst_y * 40)  + _dst_x;
    // Colour RAM: only one $D800 exists. For in-place copies (src == dst) read
    // live $D800 to preserve runtime colour cycling. For cross-bitmap copies,
    // source colour data lives at <src screen RAM> + $03E8 — the exact address
    // Pass 3 injected it to, which is bank-aware (NOT a flat src_bmp + $23E8).
    // Colour source. In-place copies (src == dst) read live $D800 so runtime
    // colour cycling is preserved. Cross-bitmap copies read the injected
    // source colour block, which now lives at bmp + 8000 (right after the
    // bitmap) — NOT at screen + $03E8. That old rule ran off the end of the
    // VIC bank for bank-2 sources and pointed at unwritten RAM, which is why
    // copied cells came out black.
    // Colour source. In-place copies (src == dst) read live $D800 so runtime
    // colour cycling is preserved. Cross-bitmap copies read the injected
    // source colour block — placement must mirror the asset injector exactly:
    // screen + $03E8 normally, bitmap + 8000 for bank 2.
    // In-place copies (src == dst) read live $D800 so runtime colour cycling is
    // preserved. Cross-bitmap copies read the injected source colour block.
    var _src_col_loc  = (_src_bmp == _dst_bmp) ? 0xD800 : _src_r.col_addr;
    var _src_col_base = _src_col_loc + (_src_y * 40) + _src_x;
    var _dst_col_base = 0xD800       + (_dst_y * 40) + _dst_x;

    // ZP scratch for runtime base pointer maths
    // $FB/$FC = src bitmap base, $FD/$FE = dst bitmap base
    // (only used when offset vars are present)
    var _need_runtime_calc = (_has_sxv || _has_syv || _has_dxv || _has_dyv);

    if (_src_mode == 1) {
        // ══════════════════════════════════════════════════════════════════
        // ASSET MODE — walk a BYTE_DATA list of 6-byte copy records.
        //
        //   record: [0] sc  [1] sr  [2] dc  [3] dr  [4] w  [5] h
        //   stride: 6 bytes.  terminator: $FF in byte [0].
        //
        // blend / copy_scr / copy_col come from the NODE and apply to every
        // record, so the copy body is specialised at compile time rather than
        // branching on a per-record mode byte. One subroutine per node.
        //
        // ZP map for this mode (all outside KERNAL scratch):
        //   $F2/$F3 = record pointer (walks the BYTE_DATA list)
        //   $F4     = sc      $F5 = sr
        //   $F6     = dc      $F7 = dr
        //   $F8     = w       $F9 = h
        //   $FA     = row counter parked across the mask lookup
        //   $FB/$FC = src ptr $FD/$FE = dst ptr
        //   $F1     = inner-loop byte count for the current row span
        // ══════════════════════════════════════════════════════════════════

        // Resolve the BYTE_DATA asset's injected base address.
        var _rec_base = 0;
        if (instance_exists(obj_asset_manager)) {
            var _am_r = obj_asset_manager;
            for (var _ri2 = 0; _ri2 < ds_list_size(_am_r.asset_list); _ri2++) {
                var _a_r = ds_list_find_value(_am_r.asset_list, _ri2);
                if (_a_r.type == "BYTE_DATA" && _a_r.name == _rec_ast) {
                    _rec_base = _a_r.address;
                    break;
                }
            }
        }

        if (_rec_base == 0) {
            show_debug_message("MOVE_BMP_BLOCK(ASSET): BYTE_DATA '" + _rec_ast + "' not found — skipping");
        } else {
            var _entry_addr = _resolve_var(_entry_v);
            var _has_entry  = (_entry_addr != 0);

            var _lbl_wlk    = _pfx + "walk";
            var _lbl_end    = _pfx + "wend";
            var _lbl_body   = _pfx + "body";

            // ── Record pointer → $F2/$F3 ──
            if (!_has_entry) {
                // No entry VAR: bake the base in. Zero runtime cost.
                array_push(_list, ["lda_imm", _rec_base & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xF2,                    _id]);
                array_push(_list, ["lda_imm", (_rec_base >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xF3,                    _id]);
            } else {
                // ENTRY VAR = GROUP INDEX (0-based). A group is every record
                // between two $FF sentinels, so group N starts immediately after
                // the Nth sentinel. Records-per-group varies, so the old
                // "offset = index * 6" arithmetic is meaningless here — instead
                // walk the table from the base, counting sentinels, and stop
                // once we've skipped ENTRY of them. That gives 255 groups from
                // a single byte with no extra data emitted, and the table format
                // is unchanged.
                //
                //   $F2/$F3 = record pointer (walks the table)
                //   $F0     = remaining groups to skip
                //
                // Group 0 skips nothing, so the loop falls straight through.
                // A malformed table (fewer groups than ENTRY asks for) walks off
                // the end — same failure mode as a bad record index before, and
                // the editor bounds ENTRY to the group count.
                var _lbl_gskip = _pfx + "gskip";  // top of the skip loop
                var _lbl_gdone = _pfx + "gdone";  // seek complete
                var _lbl_gnext = _pfx + "gnext";  // advance to next record

                array_push(_list, ["lda_imm", _rec_base & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xF2,                    _id]);
                array_push(_list, ["lda_imm", (_rec_base >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xF3,                    _id]);

                array_push(_list, ["lda_abs", _entry_addr, _id]);
                array_push(_list, ["sta_zp",  0xF0,        _id]);  // groups left to skip

                array_push(_list, ["label",   _lbl_gskip       ]);
                array_push(_list, ["lda_zp",  0xF0,        _id]);
                array_push(_list, ["beq",     _lbl_gdone,  _id]);  // 0 left -> we're there

                // Read byte [0] of the current record. $FF = sentinel = group end.
                array_push(_list, ["ldy_imm", 0,           _id]);
                array_push(_list, ["lda_izy", 0xF2,        _id]);
                array_push(_list, ["cmp_imm", 0xFF,        _id]);
                array_push(_list, ["bne",     _lbl_gnext,  _id]);  // not a sentinel -> just step
                array_push(_list, ["dec_zp",  0xF0,        _id]);  // sentinel -> one group crossed

                array_push(_list, ["label",   _lbl_gnext       ]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xF2, _id]);
                array_push(_list, ["adc_imm", 6,    _id]);
                array_push(_list, ["sta_zp",  0xF2, _id]);
                array_push(_list, ["lda_zp",  0xF3, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xF3, _id]);
                array_push(_list, ["jmp_abs", _lbl_gskip, _id]);

                array_push(_list, ["label",   _lbl_gdone       ]);
                // $F2/$F3 now points at the first record of the requested GROUP.
                // The old record-index path (base + n*6) that used to live here
                // is gone — it ran AFTER the scan and clobbered the pointer the
                // scan had just computed, so ENTRY still behaved as a raw record
                // index no matter what the scan found.
            }

            // ── WALK LOOP ──
            // Runs from the entry record to the next $FF terminator. With an
            // entry VAR the asset can hold several runs back to back, each with
            // its own $FF — the VAR picks which run gets drawn.
            array_push(_list, ["label", _lbl_wlk]);

            // Terminator check: byte [0] == $FF → done.
            array_push(_list, ["ldy_imm", 0,        _id]);
            array_push(_list, ["lda_izy", 0xF2,     _id]);
            array_push(_list, ["cmp_imm", 0xFF,     _id]);
            array_push(_list, ["beq",     _lbl_end, _id]);

            // Unpack the record into $F4-$F9.
            array_push(_list, ["sta_zp",  0xF4, _id]);  // sc
            array_push(_list, ["iny",     0,    _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["sta_zp",  0xF5, _id]);  // sr
            array_push(_list, ["iny",     0,    _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["sta_zp",  0xF6, _id]);  // dc
            array_push(_list, ["iny",     0,    _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["sta_zp",  0xF7, _id]);  // dr
            array_push(_list, ["iny",     0,    _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["sta_zp",  0xF8, _id]);  // w
            array_push(_list, ["iny",     0,    _id]);
            array_push(_list, ["lda_izy", 0xF2, _id]);
            array_push(_list, ["sta_zp",  0xF9, _id]);  // h

            // Do the copy for this record.
            array_push(_list, ["jsr", _lbl_body, _id]);

            // Advance the record pointer by 6.
            array_push(_list, ["clc",     0,    _id]);
            array_push(_list, ["lda_zp",  0xF2, _id]);
            array_push(_list, ["adc_imm", 6,    _id]);
            array_push(_list, ["sta_zp",  0xF2, _id]);
            array_push(_list, ["lda_zp",  0xF3, _id]);
            array_push(_list, ["adc_imm", 0,    _id]);
            array_push(_list, ["sta_zp",  0xF3, _id]);

            array_push(_list, ["jmp_abs", _lbl_wlk, _id]);

            array_push(_list, ["label", _lbl_end]);

            // Jump over the subroutine body — it's called, not fallen into.
            var _lbl_skip = _pfx + "bskip";
            array_push(_list, ["jmp_abs", _lbl_skip, _id]);

            // ══════════════════════════════════════════════════════════════
            // bmpblk_copy body — params in $F4-$F9, specialised to this
            // node's blend / copy_scr / copy_col flags.
            // ══════════════════════════════════════════════════════════════
            array_push(_list, ["label", _lbl_body]);

            // ── BITMAP: src ptr = src_bmp + MBBR320[sr] + MBBCOL8[sc] ──
            // Three 16-bit addends, so the carry must be chained ONE add at a
            // time. Chaining three ADCs off a single CLC silently eats the
            // intermediate carries. Accumulate into $FB/$FC and fold each
            // addend in separately.
            array_push(_list, ["ldx_zp",  0xF5,           _id]);  // sr
            array_push(_list, ["ldy_zp",  0xF4,           _id]);  // sc
            // $FB/$FC = src_bmp + row_offset
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_abx", "MBBR320_LO",   _id]);
            array_push(_list, ["adc_imm", _src_bmp & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFB,           _id]);
            array_push(_list, ["lda_abx", "MBBR320_HI",   _id]);
            array_push(_list, ["adc_imm", (_src_bmp >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFC,           _id]);
            // += col_offset (16-bit, cols 32-39 have a HI byte)
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_zp",  0xFB,           _id]);
            array_push(_list, ["adc_aby", "MBBCOL8_LO",   _id]);
            array_push(_list, ["sta_zp",  0xFB,           _id]);
            array_push(_list, ["lda_zp",  0xFC,           _id]);
            array_push(_list, ["adc_aby", "MBBCOL8_HI",   _id]);
            array_push(_list, ["sta_zp",  0xFC,           _id]);

            // ── BITMAP: dst ptr = dst_bmp + MBBR320[dr] + MBBCOL8[dc] ──
            array_push(_list, ["ldx_zp",  0xF7,           _id]);  // dr
            array_push(_list, ["ldy_zp",  0xF6,           _id]);  // dc
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_abx", "MBBR320_LO",   _id]);
            array_push(_list, ["adc_imm", _dst_bmp & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFD,           _id]);
            array_push(_list, ["lda_abx", "MBBR320_HI",   _id]);
            array_push(_list, ["adc_imm", (_dst_bmp >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFE,           _id]);
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_zp",  0xFD,           _id]);
            array_push(_list, ["adc_aby", "MBBCOL8_LO",   _id]);
            array_push(_list, ["sta_zp",  0xFD,           _id]);
            array_push(_list, ["lda_zp",  0xFE,           _id]);
            array_push(_list, ["adc_aby", "MBBCOL8_HI",   _id]);
            array_push(_list, ["sta_zp",  0xFE,           _id]);

            // Inner row span = w * 8 → $F1. w is 1..40, so w*8 is 8..320.
            // > 255 needs the page path; clamp at 31 cells (248 bytes) here and
            // let the LIT path handle wider blocks. A record with w >= 32 is
            // rejected at edit time by the node, so this is a belt-and-braces
            // clamp rather than an expected case.
            array_push(_list, ["lda_zp",  0xF8, _id]);
            array_push(_list, ["cmp_imm", 32,   _id]);
            var _lbl_wok = _pfx + "wok";
            array_push(_list, ["bcc",     _lbl_wok, _id]);
            array_push(_list, ["lda_imm", 31,       _id]);
            array_push(_list, ["label",   _lbl_wok      ]);
            array_push(_list, ["asl_a",   0,    _id]);
            array_push(_list, ["asl_a",   0,    _id]);
            array_push(_list, ["asl_a",   0,    _id]);
            array_push(_list, ["sta_zp",  0xF1, _id]);

            // ── BITMAP ROW LOOP ──
            //
            // OPAQUE takes the flat path: w*8 consecutive bytes per char row,
            // cells interleaved, no per-cell state.
            //
            // MASK00 cannot. The merged cell carries the SOURCE's palette, so
            // destination pixels surviving under the source's %00 holes must be
            // remapped onto it by luma group. That is per-cell state, so the
            // masked path walks a cell grid instead. See
            // scr_mbb_emit_mask_cells.
            var _lbl_br = _pfx + "abmr";
            var _lbl_bb = _pfx + "abmb";

            if (_blend != 0) {
                array_push(_list, ["ldx_zp",  0xF9,     _id]);  // h = row counter
                array_push(_list, ["label",   _lbl_br       ]);
                array_push(_list, ["ldy_imm", 0,        _id]);
                array_push(_list, ["label",   _lbl_bb       ]);
                array_push(_list, ["lda_izy", 0xFB,     _id]);
                array_push(_list, ["sta_izy", 0xFD,     _id]);
                array_push(_list, ["iny",     0,        _id]);
                array_push(_list, ["cpy_zp",  0xF1,     _id]);
                array_push(_list, ["bne",     _lbl_bb,  _id]);

                // Next char row: both pointers += 320. OPAQUE ONLY — this and
                // the DEX/BNE below close the flat row loop. The MASK00 path
                // owns its own row walk and never emits _lbl_br, so leaving
                // these outside the branch made the masked build fall through
                // into orphaned code and branch to an unresolved label.
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFB, _id]);
                array_push(_list, ["adc_imm", 64,   _id]);
                array_push(_list, ["sta_zp",  0xFB, _id]);
                array_push(_list, ["lda_zp",  0xFC, _id]);
                array_push(_list, ["adc_imm", 1,    _id]);
                array_push(_list, ["sta_zp",  0xFC, _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFD, _id]);
                array_push(_list, ["adc_imm", 64,   _id]);
                array_push(_list, ["sta_zp",  0xFD, _id]);
                array_push(_list, ["lda_zp",  0xFE, _id]);
                array_push(_list, ["adc_imm", 1,    _id]);
                array_push(_list, ["sta_zp",  0xFE, _id]);
                array_push(_list, ["dex",     0,       _id]);
                array_push(_list, ["bne",     _lbl_br, _id]);
            } else {
                scr_mbb_emit_mask_cells(_list, _id, _pfx, _src_scr, _src_col_loc, _dst_scr);
            }

            // ── SCREEN RAM (src cell's col1/col2) ──
            // MASK00 already wrote both palette planes per cell as part of the
            // merge — it has to, because the remap depends on knowing both
            // palettes before the bytes are combined. Running these loops again
            // would be a redundant second pass over the same bytes.
            if (_scr_on == 1 && _blend != 0) {
                var _lbl_sr = _pfx + "ascr";
                var _lbl_sb = _pfx + "ascb";
                // src scr ptr = src_scr + MBBR40[sr] + sc
                // Chain the carry one addend at a time (see the bitmap pointer
                // above) — three ADCs off one CLC eats the intermediate carry.
                array_push(_list, ["ldx_zp",  0xF5,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", _src_scr & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", (_src_scr >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFB,          _id]);
                array_push(_list, ["adc_zp",  0xF4,          _id]);
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_zp",  0xFC,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);
                // dst scr ptr = dst_scr + MBBR40[dr] + dc
                array_push(_list, ["ldx_zp",  0xF7,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", _dst_scr & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", (_dst_scr >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xFE,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFD,          _id]);
                array_push(_list, ["adc_zp",  0xF6,          _id]);
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_zp",  0xFE,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFE,          _id]);

                array_push(_list, ["ldx_zp",  0xF9,     _id]);
                array_push(_list, ["label",   _lbl_sr       ]);
                array_push(_list, ["ldy_imm", 0,        _id]);
                array_push(_list, ["label",   _lbl_sb       ]);
                array_push(_list, ["lda_izy", 0xFB,     _id]);
                array_push(_list, ["sta_izy", 0xFD,     _id]);
                array_push(_list, ["iny",     0,        _id]);
                array_push(_list, ["cpy_zp",  0xF8,     _id]);
                array_push(_list, ["bne",     _lbl_sb,  _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFB, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFB, _id]);
                array_push(_list, ["lda_zp",  0xFC, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFC, _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFD, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFD, _id]);
                array_push(_list, ["lda_zp",  0xFE, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFE, _id]);
                array_push(_list, ["dex",     0,       _id]);
                array_push(_list, ["bne",     _lbl_sr, _id]);
            }

            // ── COLOUR RAM (src cell's col3) ──
            // Skipped for MASK00 — see the screen RAM note above.
            if (_col_on && _blend != 0) {
                var _lbl_cr = _pfx + "acor";
                var _lbl_cb = _pfx + "acob";
                // src col ptr = src_col_loc + MBBR40[sr] + sc
                array_push(_list, ["ldx_zp",  0xF5,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", _src_col_loc & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", (_src_col_loc >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFB,          _id]);
                array_push(_list, ["adc_zp",  0xF4,          _id]);
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_zp",  0xFC,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);
                // dst col ptr = $D800 + MBBR40[dr] + dc
                array_push(_list, ["ldx_zp",  0xF7,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", 0x00,          _id]);
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", 0xD8,          _id]);
                array_push(_list, ["sta_zp",  0xFE,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFD,          _id]);
                array_push(_list, ["adc_zp",  0xF6,          _id]);
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_zp",  0xFE,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFE,          _id]);

                array_push(_list, ["ldx_zp",  0xF9,     _id]);
                array_push(_list, ["label",   _lbl_cr       ]);
                array_push(_list, ["ldy_imm", 0,        _id]);
                array_push(_list, ["label",   _lbl_cb       ]);
                array_push(_list, ["lda_izy", 0xFB,     _id]);
                array_push(_list, ["sta_izy", 0xFD,     _id]);
                array_push(_list, ["iny",     0,        _id]);
                array_push(_list, ["cpy_zp",  0xF8,     _id]);
                array_push(_list, ["bne",     _lbl_cb,  _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFB, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFB, _id]);
                array_push(_list, ["lda_zp",  0xFC, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFC, _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFD, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFD, _id]);
                array_push(_list, ["lda_zp",  0xFE, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFE, _id]);
                array_push(_list, ["dex",     0,       _id]);
                array_push(_list, ["bne",     _lbl_cr, _id]);
            }

            // ── COLLISION MAP (src cell's TAG -> $0400 + dst_cell) ──
            // One byte per CHAR CELL. For each cell in the w*h block, read the
            // type painted on the source cell from BBT and stamp it into screen
            // RAM at the dest cell. Screen RAM is unused in bitmap mode (VIC is
            // at $6000), so $0400 is a free collision map MACRO_COLL_ADV reads
            // directly. Rebuilt every blit, so it always matches what ENTRY drew,
            // at a flat 1000 bytes of BBT however many rooms exist.
            //
            // ZP reuses $FB/$FC (src TAG ptr) + $FD/$FE (dst screen ptr), free
            // now the pixel/screen/colour copies are done. CELL loop (w*h) —
            // far smaller than the pixel loops above.
            if (_wcoll_live) {
                var _lbl_kr = _pfx + "akcr";
                var _lbl_kb = _pfx + "akcb";

                // src TAG row base = BBT + MBBR40[sr] + sc.  MBBR40 is emitted
                // unconditionally in ASSET mode, so it exists here. Carry chained
                // one addend at a time.
                array_push(_list, ["ldx_zp",  0xF5,          _id]);  // sr
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", _bbt_base & 0xFF,        _id]);
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", (_bbt_base >> 8) & 0xFF, _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFB,          _id]);
                array_push(_list, ["adc_zp",  0xF4,          _id]);  // + sc
                array_push(_list, ["sta_zp",  0xFB,          _id]);
                array_push(_list, ["lda_zp",  0xFC,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFC,          _id]);

                // dst collision row base = $0400 + MBBR40[dr] + dc
                array_push(_list, ["ldx_zp",  0xF7,          _id]);  // dr
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_abx", "MBBR40_LO",   _id]);
                array_push(_list, ["adc_imm", 0x00,          _id]);  // $0400 low
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_abx", "MBBR40_HI",   _id]);
                array_push(_list, ["adc_imm", 0x04,          _id]);  // $0400 high
                array_push(_list, ["sta_zp",  0xFE,          _id]);
                array_push(_list, ["clc",     0,             _id]);
                array_push(_list, ["lda_zp",  0xFD,          _id]);
                array_push(_list, ["adc_zp",  0xF6,          _id]);  // + dc
                array_push(_list, ["sta_zp",  0xFD,          _id]);
                array_push(_list, ["lda_zp",  0xFE,          _id]);
                array_push(_list, ["adc_imm", 0,             _id]);
                array_push(_list, ["sta_zp",  0xFE,          _id]);

                // h rows, w cells each. Straight byte copy — a tag overwrites
                // whatever collision was there, as the pixels overwrote the
                // screen. Both pointers stride 40 to the next char row.
                array_push(_list, ["ldx_zp",  0xF9,     _id]);  // h
                array_push(_list, ["label",   _lbl_kr       ]);
                array_push(_list, ["ldy_imm", 0,        _id]);
                array_push(_list, ["label",   _lbl_kb       ]);
                array_push(_list, ["lda_izy", 0xFB,     _id]);  // BBT[src cell]
                array_push(_list, ["sta_izy", 0xFD,     _id]);  // -> $0400 + dst
                array_push(_list, ["iny",     0,        _id]);
                array_push(_list, ["cpy_zp",  0xF8,     _id]);  // w done?
                array_push(_list, ["bne",     _lbl_kb,  _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFB, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFB, _id]);
                array_push(_list, ["lda_zp",  0xFC, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFC, _id]);
                array_push(_list, ["clc",     0,    _id]);
                array_push(_list, ["lda_zp",  0xFD, _id]);
                array_push(_list, ["adc_imm", 40,   _id]);
                array_push(_list, ["sta_zp",  0xFD, _id]);
                array_push(_list, ["lda_zp",  0xFE, _id]);
                array_push(_list, ["adc_imm", 0,    _id]);
                array_push(_list, ["sta_zp",  0xFE, _id]);
                array_push(_list, ["dex",     0,       _id]);
                array_push(_list, ["bne",     _lbl_kr, _id]);
            }

            array_push(_list, ["rts", 0, _id]);
            array_push(_list, ["label", _lbl_skip]);
        }
    } else if (!_need_runtime_calc) {
        // ── FAST PATH (loop-based): near-constant size regardless of W*H ──
        // Copies char-row by char-row. Within a char row the bw cells are
        // contiguous in the bitmap (bw*8 bytes), so one inner Y-loop copies the
        // whole row span; the outer X-loop steps char rows by adding 320 to the
        // ZP pointers. Screen/colour copy bw bytes per row, stride 40.
        // $FB/$FC = src ptr, $FD/$FE = dst ptr.

        // Bitmap row span = bw * 8 bytes. When bw >= 32 this exceeds 255, so a
        // single Y counter cannot index the row. Use a full-height contiguous
        // approach instead: because src/dst blocks are stored with a 320-byte
        // char-row stride and we copy bw cells (bw*8 bytes) per row, walk one
        // char row with a byte counter that supports > 255 via a ZP loop count.
        //
        // We keep the row-by-row outer loop (X = char rows) but replace the
        // inner Y-only counter with a "copy N bytes" routine using Y wrap plus
        // a page counter held in $02. Total per row = bw*8 bytes.
        var _bm_row_span = _bw * 8;              // bytes copied per char row
        var _bm_pages    = _bm_row_span div 256; // whole 256-byte pages
        var _bm_rem      = _bm_row_span mod 256; // leftover bytes
        // Row-to-row stride is a FULL char row (40 cells * 8 = 320 bytes),
        // NOT bw*8 — the bw cells are contiguous within a char row, but the
        // next char row starts 320 bytes on. Advancing by bw*8 lands halfway
        // into the same char row and shifts every row below the first.
        var _bm_stride   = 320;
        var _bm_adv_lo   = _bm_stride & 0xFF;
        var _bm_adv_hi   = (_bm_stride >> 8) & 0xFF;

        // ── Bitmap ──
        array_push(_list, ["lda_imm", _src_bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFB,                        _id]);
        array_push(_list, ["lda_imm", (_src_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFC,                        _id]);
        array_push(_list, ["lda_imm", _dst_bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFD,                        _id]);
        array_push(_list, ["lda_imm", (_dst_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFE,                        _id]);
        array_push(_list, ["ldx_imm", _bh,              _id]);
        array_push(_list, ["label",   _pfx + "bmr"          ]);

        // Copy _bm_pages full pages (256 bytes each) via Y wrap, then _bm_rem.
        // $02 = page counter for this row.
        // OPAQUE (_blend 1): straight lda/sta.
        // MASK00 (_blend 0): merge via MCMASK00 so source %00 pairs are holes
        //   and the destination shows through them.
        if (_bm_pages > 0) {
            array_push(_list, ["lda_imm", _bm_pages,        _id]);
            array_push(_list, ["sta_zp",  0x02,             _id]);
            array_push(_list, ["ldy_imm", 0,                _id]);
            array_push(_list, ["label",   _pfx + "bmpg"         ]);
            array_push(_list, ["lda_izy", 0xFB,             _id]);
            if (_blend == 0) {
                // Preserve X (the outer row counter) across the mask lookup.
                // $F1 — NOT $02/$03: those are KERNAL keyboard-scan scratch and
                // the IRQ handler ($EA87) writes to them, which would corrupt
                // the row counter mid-copy the moment a SID/raster IRQ is live.
                array_push(_list, ["stx_zp",  0xF1,         _id]);
                array_push(_list, ["tax",     0,            _id]);
                array_push(_list, ["lda_abx", "MCMASK00",   _id]);
                array_push(_list, ["and_izy", 0xFD,         _id]);
                array_push(_list, ["ora_izy", 0xFB,         _id]);
                array_push(_list, ["ldx_zp",  0xF1,         _id]);
            }
            array_push(_list, ["sta_izy", 0xFD,             _id]);
            array_push(_list, ["iny",     0,                _id]);
            array_push(_list, ["bne",     _pfx + "bmpg",    _id]);
            // Y wrapped 256 → advance both HI bytes, dec page count, repeat
            array_push(_list, ["inc_zp",  0xFC,             _id]);
            array_push(_list, ["inc_zp",  0xFE,             _id]);
            array_push(_list, ["dec_zp",  0x02,             _id]);
            array_push(_list, ["bne",     _pfx + "bmpg",    _id]);
        }
        // Remainder bytes (Y is 0 here after wrap, or fresh if no pages)
        if (_bm_rem > 0) {
            array_push(_list, ["ldy_imm", 0,                _id]);
            array_push(_list, ["label",   _pfx + "bmrm"         ]);
            array_push(_list, ["lda_izy", 0xFB,             _id]);
            if (_blend == 0) {
                // X is the OUTER row counter for _pfx + "bmr" — TAX would
                // destroy it and the row loop would then run an arbitrary
                // number of times, walking the pointers off into memory.
                // Park it in $F1 across the mask lookup ($02/$03 are KERNAL
                // keyboard scratch — an IRQ would clobber them mid-copy).
                array_push(_list, ["stx_zp",  0xF1,         _id]);
                array_push(_list, ["tax",     0,            _id]);
                array_push(_list, ["lda_abx", "MCMASK00",   _id]);
                array_push(_list, ["and_izy", 0xFD,         _id]);
                array_push(_list, ["ora_izy", 0xFB,         _id]);
                array_push(_list, ["ldx_zp",  0xF1,         _id]);
            }
            array_push(_list, ["sta_izy", 0xFD,             _id]);
            array_push(_list, ["iny",     0,                _id]);
            array_push(_list, ["cpy_imm", _bm_rem,          _id]);
            array_push(_list, ["bne",     _pfx + "bmrm",    _id]);
        }

        // Advance src/dst to next char row. HI bytes were bumped _bm_pages
        // times by the page loop; undo those, then add the true row span so the
        // net move equals exactly bw*8 bytes.
        if (_bm_pages > 0) {
            array_push(_list, ["lda_zp",  0xFC,             _id]);
            array_push(_list, ["sec",     0,                _id]);
            array_push(_list, ["sbc_imm", _bm_pages,        _id]);
            array_push(_list, ["sta_zp",  0xFC,             _id]);
            array_push(_list, ["lda_zp",  0xFE,             _id]);
            array_push(_list, ["sec",     0,                _id]);
            array_push(_list, ["sbc_imm", _bm_pages,        _id]);
            array_push(_list, ["sta_zp",  0xFE,             _id]);
        }
        array_push(_list, ["clc",     0,                _id]); // src += span
        array_push(_list, ["lda_zp",  0xFB,             _id]);
        array_push(_list, ["adc_imm", _bm_adv_lo,       _id]);
        array_push(_list, ["sta_zp",  0xFB,             _id]);
        array_push(_list, ["lda_zp",  0xFC,             _id]);
        array_push(_list, ["adc_imm", _bm_adv_hi,       _id]);
        array_push(_list, ["sta_zp",  0xFC,             _id]);
        array_push(_list, ["clc",     0,                _id]); // dst += span
        array_push(_list, ["lda_zp",  0xFD,             _id]);
        array_push(_list, ["adc_imm", _bm_adv_lo,       _id]);
        array_push(_list, ["sta_zp",  0xFD,             _id]);
        array_push(_list, ["lda_zp",  0xFE,             _id]);
        array_push(_list, ["adc_imm", _bm_adv_hi,       _id]);
        array_push(_list, ["sta_zp",  0xFE,             _id]);
        array_push(_list, ["dex",     0,                _id]);
        array_push(_list, ["bne",     _pfx + "bmr",     _id]);

        // ── Screen RAM (src cell's col1/col2 nibbles) ──
        // Gated by copy_scr [15]. The source cell owns the palette, so this is
        // ON by default: the stamped pixels render in the colours they were
        // authored with. Turn it OFF to stamp into the destination's existing
        // palette instead.
        if (_scr_on == 1) {
        array_push(_list, ["lda_imm", _src_scr_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFB,                        _id]);
        array_push(_list, ["lda_imm", (_src_scr_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFC,                        _id]);
        array_push(_list, ["lda_imm", _dst_scr_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFD,                        _id]);
        array_push(_list, ["lda_imm", (_dst_scr_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFE,                        _id]);
        array_push(_list, ["ldx_imm", _bh,              _id]);
        array_push(_list, ["label",   _pfx + "scrr"         ]);
        array_push(_list, ["ldy_imm", 0,                _id]);
        array_push(_list, ["label",   _pfx + "scrb"         ]);
        array_push(_list, ["lda_izy", 0xFB,             _id]);
        array_push(_list, ["sta_izy", 0xFD,             _id]);
        array_push(_list, ["iny",     0,                _id]);
        array_push(_list, ["cpy_imm", _bw,              _id]);
        array_push(_list, ["bne",     _pfx + "scrb",    _id]);
        array_push(_list, ["clc",     0,                _id]);
        array_push(_list, ["lda_zp",  0xFB,             _id]);
        array_push(_list, ["adc_imm", 40,               _id]);
        array_push(_list, ["sta_zp",  0xFB,             _id]);
        array_push(_list, ["lda_zp",  0xFC,             _id]);
        array_push(_list, ["adc_imm", 0,                _id]);
        array_push(_list, ["sta_zp",  0xFC,             _id]);
        array_push(_list, ["clc",     0,                _id]);
        array_push(_list, ["lda_zp",  0xFD,             _id]);
        array_push(_list, ["adc_imm", 40,               _id]);
        array_push(_list, ["sta_zp",  0xFD,             _id]);
        array_push(_list, ["lda_zp",  0xFE,             _id]);
        array_push(_list, ["adc_imm", 0,                _id]);
        array_push(_list, ["sta_zp",  0xFE,             _id]);
        array_push(_list, ["dex",     0,                _id]);
        array_push(_list, ["bne",     _pfx + "scrr",    _id]);
        } // end if (_scr_on)

        // ── Colour RAM (src cell's col3 nibble) ──
        if (_col_on) {
            array_push(_list, ["lda_imm", _src_col_base & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFB,                        _id]);
            array_push(_list, ["lda_imm", (_src_col_base >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFC,                        _id]);
            array_push(_list, ["lda_imm", _dst_col_base & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFD,                        _id]);
            array_push(_list, ["lda_imm", (_dst_col_base >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFE,                        _id]);
            array_push(_list, ["ldx_imm", _bh,              _id]);
            array_push(_list, ["label",   _pfx + "colr"         ]);
            array_push(_list, ["ldy_imm", 0,                _id]);
            array_push(_list, ["label",   _pfx + "colb"         ]);
            array_push(_list, ["lda_izy", 0xFB,             _id]);
            array_push(_list, ["sta_izy", 0xFD,             _id]);
            array_push(_list, ["iny",     0,                _id]);
            array_push(_list, ["cpy_imm", _bw,              _id]);
            array_push(_list, ["bne",     _pfx + "colb",    _id]);
            array_push(_list, ["clc",     0,                _id]);
            array_push(_list, ["lda_zp",  0xFB,             _id]);
            array_push(_list, ["adc_imm", 40,               _id]);
            array_push(_list, ["sta_zp",  0xFB,             _id]);
            array_push(_list, ["lda_zp",  0xFC,             _id]);
            array_push(_list, ["adc_imm", 0,                _id]);
            array_push(_list, ["sta_zp",  0xFC,             _id]);
            array_push(_list, ["clc",     0,                _id]);
            array_push(_list, ["lda_zp",  0xFD,             _id]);
            array_push(_list, ["adc_imm", 40,               _id]);
            array_push(_list, ["sta_zp",  0xFD,             _id]);
            array_push(_list, ["lda_zp",  0xFE,             _id]);
            array_push(_list, ["adc_imm", 0,                _id]);
            array_push(_list, ["sta_zp",  0xFE,             _id]);
            array_push(_list, ["dex",     0,                _id]);
            array_push(_list, ["bne",     _pfx + "colr",    _id]);
        }
    } else {
        // ── RUNTIME PATH: compute base pointers with var offsets ──
        // src_addr = src_bmp_base + (sxv * 8) + (syv * 320)
        // Use $FB/$FC for src bitmap ptr, $FD/$FE for dst bitmap ptr
        // Then unroll the block copy using indexed ZP (zp),Y addressing? No —
        // simpler: compute the bitmap base, store to ZP, then emit (zp),Y for
        // each pixel. But for fixed bw/bh we can pre-bake offsets via ldy.

        // Compute SRC bitmap base into $FB/$FC
        array_push(_list, ["lda_imm", _src_bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFB,                        _id]);
        array_push(_list, ["lda_imm", (_src_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFC,                        _id]);

        // Add SXV * 8 — full 16-bit add so carry propagates to HI byte.
        // Without this, SXV >= 32 wraps within the 256-byte Y window.
       // Add SXV * 8 — 16-bit add with proper carry from LO into HI.
        // BUG FIX: LSR_A clobbers carry, so compute HI contribution into $F0
        // FIRST, then do LO add — carry from that ADC chains correctly into HI.
        if (_has_sxv) {
            // HI contribution = SXV >> 5  → stash in $F0
            array_push(_list, ["lda_abs", _sxv_addr,   _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["sta_zp",  0xF0,        _id]);
            // LO contribution = (SXV & 31) << 3, add to ZP_LO
            array_push(_list, ["lda_abs", _sxv_addr,   _id]);
            array_push(_list, ["and_imm", 0x1F,        _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["clc",     0,           _id]);
            array_push(_list, ["adc_zp",  0xFB,        _id]);
            array_push(_list, ["sta_zp",  0xFB,        _id]);
            // HI = ZP_HI + HI_contrib + carry_from_LO_ADC
            array_push(_list, ["lda_zp",  0xFC,        _id]);
            array_push(_list, ["adc_zp",  0xF0,        _id]);
            array_push(_list, ["sta_zp",  0xFC,        _id]);
        }
        // Add SYV * 320 = SYV * 256 + SYV * 64 — that's complex. Do it as
        // a small mul loop: repeat SYV times: add 320 to ptr.
        if (_has_syv) {
            var _lbl_syv = _pfx + "syvmul";
            var _lbl_skp = _pfx + "syvskp";
            array_push(_list, ["ldx_abs", _syv_addr,    _id]);
            array_push(_list, ["beq",     _lbl_skp,     _id]);
            array_push(_list, ["label",   _lbl_syv          ]);
            array_push(_list, ["clc",     0,            _id]);
            array_push(_list, ["lda_zp",  0xFB,         _id]);
            array_push(_list, ["adc_imm", 64,           _id]); // low byte of 320 = $40
            array_push(_list, ["sta_zp",  0xFB,         _id]);
            array_push(_list, ["lda_zp",  0xFC,         _id]);
            array_push(_list, ["adc_imm", 1,            _id]); // high byte of 320 = $01
            array_push(_list, ["sta_zp",  0xFC,         _id]);
            array_push(_list, ["dex",     0,            _id]);
            array_push(_list, ["bne",     _lbl_syv,     _id]);
            array_push(_list, ["label",   _lbl_skp          ]);
        }

        // Same for DST into $FD/$FE
        array_push(_list, ["lda_imm", _dst_bmp_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFD,                        _id]);
        array_push(_list, ["lda_imm", (_dst_bmp_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFE,                        _id]);

        if (_has_dxv) {
            // BUG FIX: HI contribution first into $F0, then LO add — carry chains correctly.
            array_push(_list, ["lda_abs", _dxv_addr,   _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["lsr_a",   0,           _id]);
            array_push(_list, ["sta_zp",  0xF0,        _id]);
            array_push(_list, ["lda_abs", _dxv_addr,   _id]);
            array_push(_list, ["and_imm", 0x1F,        _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["asl_a",   0,           _id]);
            array_push(_list, ["clc",     0,           _id]);
            array_push(_list, ["adc_zp",  0xFD,        _id]);
            array_push(_list, ["sta_zp",  0xFD,        _id]);
            array_push(_list, ["lda_zp",  0xFE,        _id]);
            array_push(_list, ["adc_zp",  0xF0,        _id]);
            array_push(_list, ["sta_zp",  0xFE,        _id]);
        }
        if (_has_dyv) {
            var _lbl_dyv = _pfx + "dyvmul";
            var _lbl_dsk = _pfx + "dyvskp";
            array_push(_list, ["ldx_abs", _dyv_addr,    _id]);
            array_push(_list, ["beq",     _lbl_dsk,     _id]);
            array_push(_list, ["label",   _lbl_dyv          ]);
            array_push(_list, ["clc",     0,            _id]);
            array_push(_list, ["lda_zp",  0xFD,         _id]);
            array_push(_list, ["adc_imm", 64,           _id]);
            array_push(_list, ["sta_zp",  0xFD,         _id]);
            array_push(_list, ["lda_zp",  0xFE,         _id]);
            array_push(_list, ["adc_imm", 1,            _id]);
            array_push(_list, ["sta_zp",  0xFE,         _id]);
            array_push(_list, ["dex",     0,            _id]);
            array_push(_list, ["bne",     _lbl_dyv,     _id]);
            array_push(_list, ["label",   _lbl_dsk          ]);
        }

        // Now $FB/$FC = src bitmap top-left, $FD/$FE = dst bitmap top-left.
        // For each char row 0..bh-1:
        //   For each char col 0..bw-1:
        //     For each pixel row 0..7:
        //       LDY #(col*8 + pixel_row)  ;; but Y is 8-bit and col*8+pr can be 0..(bw*8-1+7)
        //       LDA ($FB),Y / STA ($FD),Y
        //   Then advance both ZP pointers by 320 (next char row)
        // Loop-based bitmap copy ($FB/$FC = src, $FD/$FE = dst already set).
        // bw cells per char row are contiguous (bw*8 bytes); outer X steps rows.
        var _r_row_bytes = _bw * 8;
        if (_r_row_bytes > 255) {
            show_debug_message("MOVE_BMP_BLOCK: W*8 > 255 unsupported in runtime loop (W=" + string(_bw) + "), clamping");
            _r_row_bytes = 255;
        }
        array_push(_list, ["ldx_imm", _bh,            _id]);
        array_push(_list, ["label",   _pfx + "rbmr"        ]);
        array_push(_list, ["ldy_imm", 0,              _id]);
        array_push(_list, ["label",   _pfx + "rbmb"        ]);
        array_push(_list, ["lda_izy", 0xFB,           _id]);
        if (_blend == 0) {
            // MASK00 merge — X is the outer row counter, so TAX must be
            // bracketed. Park it in $F1 ($02/$03 are KERNAL keyboard-scan
            // scratch and would be clobbered by a live IRQ mid-copy).
            array_push(_list, ["stx_zp",  0xF1,         _id]);
            array_push(_list, ["tax",     0,            _id]);
            array_push(_list, ["lda_abx", "MCMASK00",   _id]);
            array_push(_list, ["and_izy", 0xFD,         _id]);
            array_push(_list, ["ora_izy", 0xFB,         _id]);
            array_push(_list, ["ldx_zp",  0xF1,         _id]);
        }
        array_push(_list, ["sta_izy", 0xFD,           _id]);
        array_push(_list, ["iny",     0,              _id]);
        array_push(_list, ["cpy_imm", _r_row_bytes,   _id]);
        array_push(_list, ["bne",     _pfx + "rbmb",  _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["lda_zp",  0xFB,           _id]);
        array_push(_list, ["adc_imm", 64,             _id]);
        array_push(_list, ["sta_zp",  0xFB,           _id]);
        array_push(_list, ["lda_zp",  0xFC,           _id]);
        array_push(_list, ["adc_imm", 1,              _id]);
        array_push(_list, ["sta_zp",  0xFC,           _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["lda_zp",  0xFD,           _id]);
        array_push(_list, ["adc_imm", 64,             _id]);
        array_push(_list, ["sta_zp",  0xFD,           _id]);
        array_push(_list, ["lda_zp",  0xFE,           _id]);
        array_push(_list, ["adc_imm", 1,              _id]);
        array_push(_list, ["sta_zp",  0xFE,           _id]);
        array_push(_list, ["dex",     0,              _id]);
        array_push(_list, ["bne",     _pfx + "rbmr",  _id]);

        // ── Screen RAM copy with runtime offsets (gated by copy_scr) ──
        // src_scr = src_scr_base + sxv + (syv * 40)
        // Reuse $FB/$FC for src screen, $FD/$FE for dst screen.
        if (_scr_on == 1) {
        array_push(_list, ["lda_imm", _src_scr_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFB,                        _id]);
        array_push(_list, ["lda_imm", (_src_scr_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFC,                        _id]);
        if (_has_sxv) {
            array_push(_list, ["lda_abs", _sxv_addr,   _id]);
            array_push(_list, ["clc",     0,           _id]);
            array_push(_list, ["adc_zp",  0xFB,        _id]);
            array_push(_list, ["sta_zp",  0xFB,        _id]);
            array_push(_list, ["lda_zp",  0xFC,        _id]);
            array_push(_list, ["adc_imm", 0,           _id]);
            array_push(_list, ["sta_zp",  0xFC,        _id]);
        }
        if (_has_syv) {
            // Add syv * 40
            var _lbl_syvs = _pfx + "syvscr";
            var _lbl_sks  = _pfx + "syvsks";
            array_push(_list, ["ldx_abs", _syv_addr,    _id]);
            array_push(_list, ["beq",     _lbl_sks,     _id]);
            array_push(_list, ["label",   _lbl_syvs         ]);
            array_push(_list, ["clc",     0,            _id]);
            array_push(_list, ["lda_zp",  0xFB,         _id]);
            array_push(_list, ["adc_imm", 40,           _id]);
            array_push(_list, ["sta_zp",  0xFB,         _id]);
            array_push(_list, ["lda_zp",  0xFC,         _id]);
            array_push(_list, ["adc_imm", 0,            _id]);
            array_push(_list, ["sta_zp",  0xFC,         _id]);
            array_push(_list, ["dex",     0,            _id]);
            array_push(_list, ["bne",     _lbl_syvs,    _id]);
            array_push(_list, ["label",   _lbl_sks          ]);
        }
        array_push(_list, ["lda_imm", _dst_scr_base & 0xFF,        _id]);
        array_push(_list, ["sta_zp",  0xFD,                        _id]);
        array_push(_list, ["lda_imm", (_dst_scr_base >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_zp",  0xFE,                        _id]);
        if (_has_dxv) {
            array_push(_list, ["lda_abs", _dxv_addr,   _id]);
            array_push(_list, ["clc",     0,           _id]);
            array_push(_list, ["adc_zp",  0xFD,        _id]);
            array_push(_list, ["sta_zp",  0xFD,        _id]);
            array_push(_list, ["lda_zp",  0xFE,        _id]);
            array_push(_list, ["adc_imm", 0,           _id]);
            array_push(_list, ["sta_zp",  0xFE,        _id]);
        }
        if (_has_dyv) {
            var _lbl_dyvs = _pfx + "dyvscr";
            var _lbl_dks  = _pfx + "dyvdks";
            array_push(_list, ["ldx_abs", _dyv_addr,    _id]);
            array_push(_list, ["beq",     _lbl_dks,     _id]);
            array_push(_list, ["label",   _lbl_dyvs         ]);
            array_push(_list, ["clc",     0,            _id]);
            array_push(_list, ["lda_zp",  0xFD,         _id]);
            array_push(_list, ["adc_imm", 40,           _id]);
            array_push(_list, ["sta_zp",  0xFD,         _id]);
            array_push(_list, ["lda_zp",  0xFE,         _id]);
            array_push(_list, ["adc_imm", 0,            _id]);
            array_push(_list, ["sta_zp",  0xFE,         _id]);
            array_push(_list, ["dex",     0,            _id]);
            array_push(_list, ["bne",     _lbl_dyvs,    _id]);
            array_push(_list, ["label",   _lbl_dks          ]);
        }
        // Loop-based screen RAM copy ($FB/$FC, $FD/$FE already set).
        array_push(_list, ["ldx_imm", _bh,            _id]);
        array_push(_list, ["label",   _pfx + "rscr"        ]);
        array_push(_list, ["ldy_imm", 0,              _id]);
        array_push(_list, ["label",   _pfx + "rscb"        ]);
        array_push(_list, ["lda_izy", 0xFB,           _id]);
        array_push(_list, ["sta_izy", 0xFD,           _id]);
        array_push(_list, ["iny",     0,              _id]);
        array_push(_list, ["cpy_imm", _bw,            _id]);
        array_push(_list, ["bne",     _pfx + "rscb",  _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["lda_zp",  0xFB,           _id]);
        array_push(_list, ["adc_imm", 40,             _id]);
        array_push(_list, ["sta_zp",  0xFB,           _id]);
        array_push(_list, ["lda_zp",  0xFC,           _id]);
        array_push(_list, ["adc_imm", 0,              _id]);
        array_push(_list, ["sta_zp",  0xFC,           _id]);
        array_push(_list, ["clc",     0,              _id]);
        array_push(_list, ["lda_zp",  0xFD,           _id]);
        array_push(_list, ["adc_imm", 40,             _id]);
        array_push(_list, ["sta_zp",  0xFD,           _id]);
        array_push(_list, ["lda_zp",  0xFE,           _id]);
        array_push(_list, ["adc_imm", 0,              _id]);
        array_push(_list, ["sta_zp",  0xFE,           _id]);
        array_push(_list, ["dex",     0,              _id]);
        array_push(_list, ["bne",     _pfx + "rscr",  _id]);
        } // end if (_scr_on)

        // ── Colour RAM ($D800) copy if enabled ──
        if (_col_on) {
            array_push(_list, ["lda_imm", _src_col_base & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFB,                        _id]);
            array_push(_list, ["lda_imm", (_src_col_base >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFC,                        _id]);
            if (_has_sxv) {
                array_push(_list, ["lda_abs", _sxv_addr,   _id]);
                array_push(_list, ["clc",     0,           _id]);
                array_push(_list, ["adc_zp",  0xFB,        _id]);
                array_push(_list, ["sta_zp",  0xFB,        _id]);
                array_push(_list, ["lda_zp",  0xFC,        _id]);
                array_push(_list, ["adc_imm", 0,           _id]);
                array_push(_list, ["sta_zp",  0xFC,        _id]);
            }
            if (_has_syv) {
                var _lbl_syvc = _pfx + "syvcol";
                var _lbl_skc  = _pfx + "syvskc";
                array_push(_list, ["ldx_abs", _syv_addr,    _id]);
                array_push(_list, ["beq",     _lbl_skc,     _id]);
                array_push(_list, ["label",   _lbl_syvc         ]);
                array_push(_list, ["clc",     0,            _id]);
                array_push(_list, ["lda_zp",  0xFB,         _id]);
                array_push(_list, ["adc_imm", 40,           _id]);
                array_push(_list, ["sta_zp",  0xFB,         _id]);
                array_push(_list, ["lda_zp",  0xFC,         _id]);
                array_push(_list, ["adc_imm", 0,            _id]);
                array_push(_list, ["sta_zp",  0xFC,         _id]);
                array_push(_list, ["dex",     0,            _id]);
                array_push(_list, ["bne",     _lbl_syvc,    _id]);
                array_push(_list, ["label",   _lbl_skc          ]);
            }
            array_push(_list, ["lda_imm", _dst_col_base & 0xFF,        _id]);
            array_push(_list, ["sta_zp",  0xFD,                        _id]);
            array_push(_list, ["lda_imm", (_dst_col_base >> 8) & 0xFF, _id]);
            array_push(_list, ["sta_zp",  0xFE,                        _id]);
            if (_has_dxv) {
                array_push(_list, ["lda_abs", _dxv_addr,   _id]);
                array_push(_list, ["clc",     0,           _id]);
                array_push(_list, ["adc_zp",  0xFD,        _id]);
                array_push(_list, ["sta_zp",  0xFD,        _id]);
                array_push(_list, ["lda_zp",  0xFE,        _id]);
                array_push(_list, ["adc_imm", 0,           _id]);
                array_push(_list, ["sta_zp",  0xFE,        _id]);
            }
            if (_has_dyv) {
                var _lbl_dyvc = _pfx + "dyvcol";
                var _lbl_dkc  = _pfx + "dyvdkc";
                array_push(_list, ["ldx_abs", _dyv_addr,    _id]);
                array_push(_list, ["beq",     _lbl_dkc,     _id]);
                array_push(_list, ["label",   _lbl_dyvc         ]);
                array_push(_list, ["clc",     0,            _id]);
                array_push(_list, ["lda_zp",  0xFD,         _id]);
                array_push(_list, ["adc_imm", 40,           _id]);
                array_push(_list, ["sta_zp",  0xFD,         _id]);
                array_push(_list, ["lda_zp",  0xFE,         _id]);
                array_push(_list, ["adc_imm", 0,            _id]);
                array_push(_list, ["sta_zp",  0xFE,         _id]);
                array_push(_list, ["dex",     0,            _id]);
                array_push(_list, ["bne",     _lbl_dyvc,    _id]);
                array_push(_list, ["label",   _lbl_dkc          ]);
            }
            // Loop-based colour RAM copy ($FB/$FC, $FD/$FE already set).
            array_push(_list, ["ldx_imm", _bh,            _id]);
            array_push(_list, ["label",   _pfx + "rcor"        ]);
            array_push(_list, ["ldy_imm", 0,              _id]);
            array_push(_list, ["label",   _pfx + "rcob"        ]);
            array_push(_list, ["lda_izy", 0xFB,           _id]);
            array_push(_list, ["sta_izy", 0xFD,           _id]);
            array_push(_list, ["iny",     0,              _id]);
            array_push(_list, ["cpy_imm", _bw,            _id]);
            array_push(_list, ["bne",     _pfx + "rcob",  _id]);
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_zp",  0xFB,           _id]);
            array_push(_list, ["adc_imm", 40,             _id]);
            array_push(_list, ["sta_zp",  0xFB,           _id]);
            array_push(_list, ["lda_zp",  0xFC,           _id]);
            array_push(_list, ["adc_imm", 0,              _id]);
            array_push(_list, ["sta_zp",  0xFC,           _id]);
            array_push(_list, ["clc",     0,              _id]);
            array_push(_list, ["lda_zp",  0xFD,           _id]);
            array_push(_list, ["adc_imm", 40,             _id]);
            array_push(_list, ["sta_zp",  0xFD,           _id]);
            array_push(_list, ["lda_zp",  0xFE,           _id]);
            array_push(_list, ["adc_imm", 0,              _id]);
            array_push(_list, ["sta_zp",  0xFE,           _id]);
            array_push(_list, ["dex",     0,              _id]);
            array_push(_list, ["bne",     _pfx + "rcor",  _id]);
       }
    }

    // Restore default banking if we changed it
    if (_needs_basic_off) {
        array_push(_list, ["lda_imm", 0x37, _id]);
        array_push(_list, ["sta_zp",  0x01, _id]);
    }

    array_push(_list, ["cli", 0, _id]);
} break;

// --------------------------------------------------------
// MACRO_MOVE_MEM
// Copies a range of bytes from [src_start..src_end) to dst at runtime.
// Unrolled if <=8 bytes, otherwise page-aware loop (capped at 1024 bytes).
// Forward copy only — overlapping ranges with dst > src will corrupt.
// --------------------------------------------------------
case "MACRO_MOVE_MEM": {
    var _id     = _curr;
    var _src_s  = is_real(_curr.instructions[0][1]) ? real(_curr.instructions[0][1]) : 0xC000;
    var _src_e  = is_real(_curr.instructions[0][2]) ? real(_curr.instructions[0][2]) : 0xC100;
    var _dst    = is_real(_curr.instructions[0][3]) ? real(_curr.instructions[0][3]) : 0x0500;

    if (_src_e < _src_s) _src_e = _src_s;
    var _len = (_src_e - _src_s) + 1;  // inclusive: end byte is copied
    if (_len > 1024) _len = 1024;
    if (_len <= 0) break;

    if (_len <= 8) {
        // Unrolled: LDA abs / STA abs per byte (6 bytes each)
        for (var _bi = 0; _bi < _len; _bi++) {
            array_push(_list, ["lda_abs", _src_s + _bi, _id]);
            array_push(_list, ["sta_abs", _dst   + _bi, _id]);
        }
    } else {
        // Page-aware loop using X as index
        var _pfx       = "mvm_" + string(real(_id)) + "_";
        var _pages     = _len div 256;
        var _remainder = _len mod 256;

        // Full 256-byte pages
        for (var _pg = 0; _pg < _pages; _pg++) {
            var _lbl       = _pfx + "p" + string(_pg);
            var _page_src  = _src_s + (_pg * 256);
            var _page_dst  = _dst   + (_pg * 256);
            array_push(_list, ["ldx_imm", 0,         _id]);
            array_push(_list, ["label",   _lbl           ]);
            array_push(_list, ["lda_abx", _page_src, _id]);
            array_push(_list, ["sta_abx", _page_dst, _id]);
            array_push(_list, ["inx",     0,         _id]);
            array_push(_list, ["bne",     _lbl,      _id]);
        }
        // Remainder (1..255 bytes)
        if (_remainder > 0) {
            var _lbl_r      = _pfx + "r";
            var _rem_src    = _src_s + (_pages * 256);
            var _rem_dst    = _dst   + (_pages * 256);
            array_push(_list, ["ldx_imm", 0,           _id]);
            array_push(_list, ["label",   _lbl_r           ]);
            array_push(_list, ["lda_abx", _rem_src,    _id]);
            array_push(_list, ["sta_abx", _rem_dst,    _id]);
            array_push(_list, ["inx",     0,           _id]);
            array_push(_list, ["cpx_imm", _remainder,  _id]);
            array_push(_list, ["bne",     _lbl_r,      _id]);
        }
    }
} break;
		  
			    // --------------------------------------------------------
                // DEFAULT - pass instructions through directly
                // --------------------------------------------------------
                default: {


                    for (var _j = 0; _j < array_length(_curr.instructions); _j++) {
                        var _row = _curr.instructions[_j];
                        // Kernal pseudo-label resolution: a plain jsr whose operand
                        // matches a Kernal routine name emits the literal address.
                        if (array_length(_row) > 1
                        &&  string_lower(string(_row[0])) == "jsr"
                        &&  is_string(_row[1])) {
                            var _krn_addr = scr_kernal_routine_addr(_row[1]);
                            if (_krn_addr != -1) {
                                var _krn_row = ["jsr", _krn_addr, _curr];
                                array_push(_list, _krn_row);
                                continue;
                            }
                        }
                        array_push(_list, _row);
                    }
                } break;

            } // end switch

            // ------------------------------------------------------------
            // TRAVERSAL
            // ------------------------------------------------------------
            var _next     = noone;
            var _best_y   = 999999;
            var _curr_ref = _curr;
            with (obj_c64_node) {
                if (id != _curr_ref && is_connected && y > _curr_ref.y && y < _best_y) {
                    var _belongs = (_org_ref == noone) ? (org_parent == noone) : (org_parent == _org_ref);
                    if (_belongs) {
                        _best_y = y;
                        _next   = id;
                    }
                }
            }
            _curr = _next;
            _guard++;
        }
		
		if (_org_ref == noone) {
		    var _has_any_nodes = false;
		    with (obj_c64_node) {
		        if (is_connected && org_parent == noone && node_type != "INIT") {
		            _has_any_nodes = true;
		            break;
		        }
		    }
		    if (!_has_any_nodes) {
		        array_push(_list, ["rts", 0]);
		    }
		}
		
	
		
    }; // end _walk_spine
	
	

    // ================================================================
    // PASS 1: MAIN SPINE
    // ================================================================
    var _init = noone;
    with (obj_c64_node) {
        if (node_type == "INIT" && x > 160) _init = id;
    }
    if (instance_exists(_init)) {
        _walk_spine(_init, instruction_list, noone);
    }

// ================================================================
// PASS 2: SECONDARY ORG SPINES
// ================================================================
var _org_nodes = [];
with (obj_c64_node) {
    if (node_type == "ORG") array_push(_org_nodes, id);
}
array_sort(_org_nodes, function(a, b) { return a.y - b.y; });
for (var _oi = 0; _oi < array_length(_org_nodes); _oi++) {
    with (_org_nodes[_oi]) {
        if (node_type == "ORG") {
            var _org_ref      = id;
            var _has_children = false;
            with (obj_c64_node) {
                if (org_parent == _org_ref && is_connected) { _has_children = true; break; }
            }
            if (!_has_children) continue;

            array_push(instruction_list, ["org", pc_address]);

            var _first_child = noone;
            var _best_y      = 999999;
            with (obj_c64_node) {
                if (org_parent == _org_ref && is_connected && y < _best_y) {
                    _best_y      = y;
                    _first_child = id;
                }
            }
            if (instance_exists(_first_child)) {
                _walk_spine(_first_child, instruction_list, _org_ref);
                array_push(instruction_list, ["org", -2]); // restore PC after ORG block
            }
        }
    }
}

// ================================================================
	// PASS 2.5: NEW_STR NODES — emit string bytes at their pc_address
	// Walk each VARIABLES ORG, recompute addresses on the fly so we
	// don't rely on stale pc_address values from the previous frame.
	// ================================================================
	with (obj_c64_node) {
	    if (node_type == "ORG" && node_title == "VARIABLES") {
	        var _str_org     = id;
	        var _str_base    = pc_address;
	        var _str_children = [];
	        with (obj_c64_node) {
	            if (org_parent == _str_org && (node_type == "NAMED_LOC" || node_type == "NEW_STR"))
	                array_push(_str_children, id);
	        }
	        array_sort(_str_children, function(a, b) { return a.y - b.y; });

	        var _str_pc = _str_base;
	        for (var _sci = 0; _sci < array_length(_str_children); _sci++) {
	            var _sc = _str_children[_sci];
	            if (_sc.node_type == "NAMED_LOC") {
	                var _sc_meta = scr_nloc_find_meta(string(_sc.instructions[0][1]));
	                if (_sc_meta != undefined) {
	                    var _sc_enc = variable_struct_exists(_sc_meta, "encoding") ? _sc_meta.encoding : "byte";
	                    if (_sc_enc == "bcd" || _sc_enc == "bcd3")       _str_pc += 3;
	                    else if (_sc_enc == "word" || _sc_enc == "bcd2") _str_pc += 2;
	                    else                                              _str_pc += 1;
	                } else {
	                    _str_pc += 1;
	                }
	                continue;
	            }
	            // NEW_STR
	            var _use_as2 = (array_length(_sc.instructions[0]) > 4 && is_real(_sc.instructions[0][4])) ? real(_sc.instructions[0][4]) : 0;
	            var _str2    = (array_length(_sc.instructions[0]) > 3) ? string(_sc.instructions[0][3]) : "";
	            if (_use_as2 == 1) {
	                var _asname2 = (array_length(_sc.instructions[0]) > 5) ? string(_sc.instructions[0][5]) : "";
	                if (_asname2 != "" && instance_exists(obj_asset_manager)) {
	                    var _am3 = obj_asset_manager;
	                    for (var _ai3 = 0; _ai3 < ds_list_size(_am3.asset_list); _ai3++) {
	                        var _a3 = ds_list_find_value(_am3.asset_list, _ai3);
	                        if (_a3.type == "TEXT_DATA" && _a3.name == _asname2) {
	                            _str2 = (variable_struct_exists(_a3, "meta") && variable_struct_exists(_a3.meta, "text"))
	                                    ? string(_a3.meta.text) : "";
	                            break;
	                        }
	                    }
	                }
	            }
	            _str2 = string_replace_all(_str2, "\n", "");
	            _str2 = string_replace_all(_str2, "\r", "");
	            var _max3 = min(string_length(_str2), (_use_as2 == 0) ? 40 : 512);

	            array_push(instruction_list, ["org", _str_pc]);
	            for (var _si3 = 1; _si3 <= _max3; _si3++) {
	                var _b3 = string_ord_at(_str2, _si3);
	                if      (_b3 >= 65  && _b3 <= 90)  _b3 -= 64;
	                else if (_b3 >= 97  && _b3 <= 122) _b3 -= 96;
	                else if (_b3 == 163 || _b3 == 100) _b3 = 28;
	                array_push(instruction_list, ["byte", _b3]);
	            }
	            //array_push(instruction_list, ["byte", 0x00]);
	            _str_pc += _max3;
	        }
	    }
	}
	     

	// ================================================================
	// PASS 3+: ALL ASSETS - sorted by address ascending
	// ================================================================
	if (instance_exists(obj_asset_manager)) {
	    var _used_bmp = ds_map_create();
	    var _used_sid = ds_map_create();
	    var _used_spr = ds_map_create();
		var _used_chr = ds_map_create();
		var _used_map = ds_map_create();
		var _used_str  = ds_map_create();
		var _used_byte = ds_map_create();
		var _used_sfx = ds_map_create();
    
	    with (obj_c64_node) {
	        if (!is_connected) continue;
	        if (node_type == "MACRO_BMP") {
	            var _n = string(instructions[0][1]);
	            if (_n != "") _used_bmp[? _n] = true;
	        }
	        if (node_type == "MACRO_MAP") {
	            var _map_node_name = string(instructions[0][1]);
	            if (_map_node_name != "" && instance_exists(obj_asset_manager)) {
	                var _am_scan = obj_asset_manager;
	                for (var _ai_scan = 0; _ai_scan < ds_list_size(_am_scan.asset_list); _ai_scan++) {
	                    var _a_scan = ds_list_find_value(_am_scan.asset_list, _ai_scan);
	                    if (_a_scan.type == "MAP_DATA" && _a_scan.name == _map_node_name) {
	                        if (variable_struct_exists(_a_scan.meta, "chr_asset") && _a_scan.meta.chr_asset != "") {
	                            _used_chr[? _a_scan.meta.chr_asset] = true;
	                            show_debug_message("PASS3: auto-marking chr_asset='" + _a_scan.meta.chr_asset + "' as used via MACRO_MAP linked charset");
	                        }
	                        break;
	                    }
	                }
	            }
	        }
			if (node_type == "MACRO_SID") {
            var _n = string(instructions[0][1]);
            if (_n != "") _used_sid[? _n] = true;
            else {
                // Name not yet committed — mark all SID_MUSIC assets as used
                if (instance_exists(obj_asset_manager)) {
                    var _fam = obj_asset_manager;
                    for (var _fai = 0; _fai < ds_list_size(_fam.asset_list); _fai++) {
                        var _fa = ds_list_find_value(_fam.asset_list, _fai);
                        if (_fa.type == "SID_MUSIC" || _fa.type == "SID_SFX")
                            _used_sid[? _fa.name] = true;
                    }
                }
            }
		}
		
		if (node_type == "MACRO_LOADER") {
		    var _org_n = string(instructions[0][1]);
		    var _file_n = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "";
		    // The LOAD_ORG itself isn't a binary asset — it's a manifest.
		    // The linked file IS the asset we need emitted. Mark it as used.
		    if (_file_n != "" && instance_exists(obj_asset_manager)) {
		        var _am_ldr = obj_asset_manager;
		        for (var _ai_ldr = 0; _ai_ldr < ds_list_size(_am_ldr.asset_list); _ai_ldr++) {
		            var _a_ldr = ds_list_find_value(_am_ldr.asset_list, _ai_ldr);
		            if (_a_ldr.name == _file_n) {
		                if      (_a_ldr.type == "BITMAP" || _a_ldr.type == "BITMAP_KLA") _used_bmp[? _file_n] = true;
		                else if (_a_ldr.type == "SID_MUSIC" || _a_ldr.type == "SID_SFX") _used_sid[? _file_n] = true;
		                else if (_a_ldr.type == "SPRITE_SET")                            _used_spr[? _file_n] = true;
		                else if (_a_ldr.type == "CHAR_SET")                              _used_chr[? _file_n] = true;
		                else if (_a_ldr.type == "MAP_DATA")                              _used_map[? _file_n] = true;
		                else if (_a_ldr.type == "TEXT_DATA")                             _used_str[? _file_n] = true;
		                else if (_a_ldr.type == "SFX_DATA")                              _used_sfx[? _file_n] = true;
		                break;
		            }
		        }
		    }
		}
		
		
		
			if (node_type == "MACRO_SFX") {
			 var _n = string(instructions[0][1]);
			 if (_n != "") _used_sfx[? _n] = true;
			}
	        if (node_type == "MACRO_SPR") {
	            var _n = string(instructions[0][1]);
	            if (_n != "") _used_spr[? _n] = true;
	        }
	        if (node_type == "MACRO_CHR") {
            var _n = string(instructions[0][1]);
            if (_n != "") _used_chr[? _n] = true;
        }
        if (node_type == "MACRO_TEXT_SCROLL") {
            var _n = (array_length(instructions[0]) > 13) ? string(instructions[0][13]) : "";
            if (_n != "") _used_chr[? _n] = true;
            
            // Flag the text asset for export if we are in ASSET mode
            var _src = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
            if (_src == 1) {
                var _txt_asset = (array_length(instructions[0]) > 10) ? string(instructions[0][10]) : "";
                if (_txt_asset != "") _used_str[? _txt_asset] = true;
            }
        }
        if (node_type == "MACRO_PRINT") {
            // Flag TEXT_DATA asset for export if MACRO_PRINT is in asset mode
            var _src_p = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
            if (_src_p == 1) {
                var _ap = (array_length(instructions[0]) > 10) ? string(instructions[0][10]) : "";
                if (_ap != "") _used_str[? _ap] = true;
            }
        }
			if (node_type == "MACRO_MAP") {
			    var _n = string(instructions[0][1]);
			    if (_n != "") _used_map[? _n] = true;
			}
			if (node_type == "BYTE_DATA_NODE") {
			    var _n = string(instructions[0][1]);
			    if (_n != "") _used_byte[? _n] = true;
			}
			if (node_type == "NEW_STR") {
			    var _use_as = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
			    if (_use_as == 1) {
			        var _n = (array_length(instructions[0]) > 5) ? string(instructions[0][5]) : "";
			        if (_n != "") _used_str[? _n] = true;
			    }
			}
	    }

	    var _load_org_linked = ds_map_create();
	    if (instance_exists(obj_asset_manager)) {
	        var _am_lo = obj_asset_manager;
	        for (var _loi = 0; _loi < ds_list_size(_am_lo.asset_list); _loi++) {
	            var _loa = ds_list_find_value(_am_lo.asset_list, _loi);
	            if (_loa.type != "LOAD_ORG") continue;
	            if (!variable_struct_exists(_loa, "linked_assets")) continue;
	            for (var _loli = 0; _loli < array_length(_loa.linked_assets); _loli++) {
	                var _lolink = _loa.linked_assets[_loli];
	                if (variable_struct_exists(_lolink, "asset_name") && _lolink.asset_name != "") {
	                    ds_map_replace(_load_org_linked, _lolink.asset_name, true);
	                }
	            }
	        }
	    }

	    var _all_assets = [];
	    var _am = obj_asset_manager;
	    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	        var _a = ds_list_find_value(_am.asset_list, _ai);

			if ((_a.type == "BITMAP" || _a.type == "BITMAP_KLA") && (ds_map_exists(_used_bmp, _a.name) && !ds_map_exists(_load_org_linked, _a.name))) array_push(_all_assets, _a);
			if (_a.type == "SID_MUSIC" || _a.type == "SID_SFX") array_push(_all_assets, _a);
	        if (_a.type == "SPRITE_SET" && (ds_map_exists(_used_spr, _a.name) || ds_map_exists(_load_org_linked, _a.name))) array_push(_all_assets, _a);
		    if (_a.type == "CHAR_SET"   && (ds_map_exists(_used_chr, _a.name) || ds_map_exists(_load_org_linked, _a.name))) array_push(_all_assets, _a);
		    if (_a.type == "MAP_DATA"   && (ds_map_exists(_used_map, _a.name) || ds_map_exists(_load_org_linked, _a.name))) array_push(_all_assets, _a);
			if (_a.type == "TEXT_DATA"  && (ds_map_exists(_used_str,  _a.name) || ds_map_exists(_load_org_linked, _a.name))) array_push(_all_assets, _a);
			if (_a.type == "BYTE_DATA"  ) array_push(_all_assets, _a);
			if (_a.type == "SFX_DATA" && ds_map_exists(_used_sfx, _a.name) && !ds_map_exists(_load_org_linked, _a.name)) array_push(_all_assets, _a);
			if (_a.type == "SFX_DATA" && ds_map_exists(_load_org_linked, _a.name)) array_push(_all_assets, _a);
	    }
    
	    ds_map_destroy(_used_bmp);
	    ds_map_destroy(_used_sid);
	    ds_map_destroy(_used_spr);
		ds_map_destroy(_used_chr);
		ds_map_destroy(_used_map);
		ds_map_destroy(_used_str);
		ds_map_destroy(_used_byte);
	    ds_map_destroy(_used_sfx);

	    array_sort(_all_assets, function(_a, _b) { return _a.address - _b.address; });

	    for (var _ai = 0; _ai < array_length(_all_assets); _ai++) {
			var _a   = _all_assets[_ai];
	        var _buf = _a.buffer;
	        if (!buffer_exists(_buf)) continue;
	        var _sz  = buffer_get_size(_buf);
	        if (_sz < 1) continue;

array_push(instruction_list, ["org", _a.address]);

if (_a.type == "BITMAP" || _a.type == "BITMAP_KLA") {
    // Region layout is owned by scr_bmp_regions — do NOT recompute it here.
    // MACRO_BMP, MACRO_MOVE_BMP_BLOCK and the memory bar all read from the
    // same helper, so a change there propagates everywhere at once. Three
    // separate hand-rolled copies of this maths is exactly what let the
    // bank-2 colour block run off the end of the VIC bank unnoticed.
    var _br      = scr_bmp_regions(_a.address);
    var _bmp_scr = _br.scr_addr;
    var _bmp_col = _br.col_addr;

    // Bitmap data: buffer bytes 2-8001. The org for _a.address was already
    // pushed by the caller, so this lands at the base.
    for (var _bb = 2; _bb < 8002; _bb++) {
        array_push(instruction_list, ["byte", (_bb < _sz) ? buffer_peek(_buf, _bb, buffer_u8) : 0]);
    }
    // Screen RAM: inject at the VIC-legal 1K slot.
    array_push(instruction_list, ["org", _bmp_scr]);
    for (var _bb = 8002; _bb < 9002; _bb++) {
        array_push(instruction_list, ["byte", (_bb < _sz) ? buffer_peek(_buf, _bb, buffer_u8) : 0]);
    }
    // Colour SOURCE block. The VIC never reads this — MACRO_BMP copies it to
    // $D800 at startup and MOVE_BMP_BLOCK reads from it — so it only needs to
    // be CPU-visible and unclaimed. scr_bmp_regions puts it after the screen
    // block in banks 0/1/3, and after the BITMAP in bank 2 (whose screen sits
    // at the top of the bank, so +$03E8 would overrun into $C000+).
    array_push(instruction_list, ["org", _bmp_col]);
    for (var _bb = 9002; _bb < 10002; _bb++) {
        array_push(instruction_list, ["byte", (_bb < _sz) ? buffer_peek(_buf, _bb, buffer_u8) : 0]);
    }
        

} else if (_a.type == "SID_MUSIC") {
            show_debug_message("SID EMIT: sz=" + string(_sz) + " b0=" + string(buffer_peek(_buf, 0, buffer_u8)) + " b6=" + string(buffer_peek(_buf, 6, buffer_u8)));
            if (_sz < 10) continue;;
            var _header_size = (buffer_peek(_buf, 6, buffer_u8) << 8) | buffer_peek(_buf, 7, buffer_u8);
            if (_header_size != 0x76 && _header_size != 0x7C) _header_size = 0x76;
            var _raw_load   = (buffer_peek(_buf, 8, buffer_u8) << 8) | buffer_peek(_buf, 9, buffer_u8);
            var _data_start = (_raw_load == 0) ? _header_size + 2 : _header_size;

            for (var _bb = _data_start; _bb < _sz; _bb++) {
                array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
            }
} else if (_a.type == "SID_SFX") {
            // Raw GT BIN — skip 2-byte PRG load address header if present
            var _sfx_start = 0;
            var _b0 = buffer_peek(_buf, 0, buffer_u8);
            var _b1 = buffer_peek(_buf, 1, buffer_u8);
            var _addr_lo = _a.address & 0xFF;
            var _addr_hi = (_a.address >> 8) & 0xFF;

            if (_sz > 2 && _b0 == _addr_lo && _b1 == _addr_hi) {
                _sfx_start = 2;

            } else {
                
            }
            for (var _bb = _sfx_start; _bb < _sz; _bb++) {
                array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
            }
			
		    } else if (_a.type == "SPRITE_SET") {
	            for (var _bb = 0; _bb < _sz; _bb++) {
	                array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
	            }
			    } else if (_a.type == "CHAR_SET") {
		    var _chr_inject_sz = min(_sz, 2048);
		    for (var _bb = 0; _bb < _chr_inject_sz; _bb++) {
		        array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
		    }
			} else if (_a.type == "BYTE_DATA") {
			    for (var _bb = 0; _bb < _sz; _bb++) {
			        array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
			    }
				
			} else if (_a.type == "TEXT_DATA") {
			    // Re-flush to guarantee screencode-converted bytes. The buffer
			    // may currently hold raw PETSCII from scr_asset_txt_import (on
			    // .txt import) which never went through the inline editor's
			    // close-flush. scr_asset_text_flush rebuilds _a.buffer as
			    // screencodes + trailing null, matching the MACRO_TEXT_SCROLL
			    // encoding exactly.
			    scr_asset_text_flush(_a);
			    _buf = _a.buffer;
			    _sz  = buffer_get_size(_buf);
			    for (var _bb = 0; _bb < _sz; _bb++) {
			        array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
			    }
				
			} else if (_a.type == "SFX_DATA") {
                if (!ds_map_exists(_load_org_linked, _a.name) && variable_struct_exists(_a.meta, "instruments")) {
                    var _instrs = _a.meta.instruments;
                    for (var _ii = 0; _ii < array_length(_instrs); _ii++) {
                        var _ins  = _instrs[_ii];
                        var _blob = scr_sfx_data_instrument_blob(_ins);
                        array_push(instruction_list, ["label", "sfxdata_" + _a.name + "_" + string(_ii)]);
                        for (var _bi = 0; _bi < array_length(_blob); _bi++) {
                            array_push(instruction_list, ["byte", _blob[_bi]]);
                        }
                    }
                }
				
			} else if (_a.type == "MAP_DATA") {
		    // Original raw inject — untouched, MACRO_MAP uses this
		    for (var _bb = 0; _bb < _sz; _bb++) {
		        array_push(instruction_list, ["byte", buffer_peek(_buf, _bb, buffer_u8)]);
		    }

		    // Transposed copy immediately after — MACRO_SCROLL uses this
		    var _mw  = _a.meta.map_w;
		    var _mh  = _a.meta.map_h;
		    var _msz = _mw * _mh;
		    var _transposed_base = _a.address + (_msz * 2); // after both planes
		    array_push(instruction_list, ["org", _transposed_base]);

		    // Char plane transposed
		    for (var _col = 0; _col < _mw; _col++) {
		        for (var _row = 0; _row < _mh; _row++) {
		            array_push(instruction_list, ["byte",
		                buffer_peek(_buf, _row * _mw + _col, buffer_u8)]);
		        }
		    }
		    // Colour plane transposed
		    for (var _col = 0; _col < _mw; _col++) {
		        for (var _row = 0; _row < _mh; _row++) {
		            array_push(instruction_list, ["byte",
		                buffer_peek(_buf, _msz + _row * _mw + _col, buffer_u8)]);
		        }
		    }

		    // ── COLL_ADV support: tile-type table + global row LUTs ──
		    // Source tile_types from first CHAR_SET asset (same source as legacy MACRO_COLLISION).
		    // Emitted only if the charset actually has non-zero tile_types.
		    var _ca_tile_types = undefined;
		    if (instance_exists(obj_asset_manager)) {
		        var _am_ca = obj_asset_manager;
		        for (var _cai = 0; _cai < ds_list_size(_am_ca.asset_list); _cai++) {
		            var _ca = ds_list_find_value(_am_ca.asset_list, _cai);
		            if (_ca.type == "CHAR_SET") {
		                if (variable_struct_exists(_ca.meta, "tile_types") && is_array(_ca.meta.tile_types)) {
		                    _ca_tile_types = _ca.meta.tile_types;
		                }
		                break;
		            }
		        }
		    }

		    var _has_any_types = false;
		    if (is_array(_ca_tile_types)) {
		        for (var _tti = 0; _tti < array_length(_ca_tile_types); _tti++) {
		            if (_ca_tile_types[_tti] != 0) { _has_any_types = true; break; }
		        }
		    }

		    if (_has_any_types) {
		        // Pad PC to a natural boundary — assembler emits the label at "wherever we are now"
		        // Tile-type sparse table: <map_name>_TILE_TYPES
		        var _tbl_label = string(_a.name) + "_TILE_TYPES";
		        array_push(instruction_list, ["label", _tbl_label]);
		        var _emit_count = 0;
		        for (var _tti = 0; _tti < array_length(_ca_tile_types); _tti++) {
		            if (_ca_tile_types[_tti] != 0) {
		                array_push(instruction_list, ["byte", _tti & 0xFF]);
		                array_push(instruction_list, ["byte", real(_ca_tile_types[_tti]) & 0xFF]);
		                _emit_count++;
		            }
		        }
		        array_push(instruction_list, ["byte", 0xFF]); // sentinel
		        show_debug_message("MAP_DATA: emitted " + _tbl_label + " — " + string(_emit_count) + " pairs");

		        // Global row LUTs — emit once, first map wins
		        if (!variable_global_exists("coll_row_luts_emitted") || global.coll_row_luts_emitted == false) {
		            array_push(instruction_list, ["label", "COLL_ROW_LO"]);
		            var _row_lo = [0x00,0x28,0x50,0x78,0xA0,0xC8,0xF0,0x18,0x40,0x68,0x90,0xB8,0xE0,0x08,0x30,0x58,0x80,0xA8,0xD0,0xF8,0x20,0x48,0x70,0x98,0xC0];
		            for (var _ri = 0; _ri < 25; _ri++) array_push(instruction_list, ["byte", _row_lo[_ri]]);
		            array_push(instruction_list, ["label", "COLL_ROW_HI"]);
		            var _row_hi = [0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x05,0x05,0x05,0x05,0x05,0x05,0x06,0x06,0x06,0x06,0x06,0x06,0x06,0x07,0x07,0x07,0x07,0x07];
		            for (var _ri = 0; _ri < 25; _ri++) array_push(instruction_list, ["byte", _row_hi[_ri]]);
		            global.coll_row_luts_emitted = true;
		            show_debug_message("MAP_DATA: emitted COLL_ROW_LO + COLL_ROW_HI (global, first map)");
		        }
		    } else {
		        show_debug_message("MAP_DATA: skipping " + string(_a.name) + "_TILE_TYPES (no tile_types in first CHAR_SET)");
			    }
			}
		}
	}
	ds_map_destroy(_load_org_linked);

	// ================================================================
    // FALLBACK: INJECT NULLSID.SID IF REQUIRED
    // ================================================================
    if (global.inject_null_sid) {
        var _nullsid_path = "C64DMResources/SID/NULLSID.sid";
        if (file_exists(_nullsid_path)) {
            var _null_buf = buffer_load(_nullsid_path);
            var _sz = buffer_get_size(_null_buf);
            if (_sz > 0x7E) {
                array_push(instruction_list, ["org", 0x1000]);
                var _header_size = (buffer_peek(_null_buf, 6, buffer_u8) << 8) | buffer_peek(_null_buf, 7, buffer_u8);
                if (_header_size != 0x76 && _header_size != 0x7C) _header_size = 0x76;
                var _raw_load   = (buffer_peek(_null_buf, 8, buffer_u8) << 8) | buffer_peek(_null_buf, 9, buffer_u8);
                var _data_start = (_raw_load == 0) ? _header_size + 2 : _header_size;
                for (var _bb = _data_start; _bb < _sz; _bb++) {
                    array_push(instruction_list, ["byte", buffer_peek(_null_buf, _bb, buffer_u8)]);
                }
            }
buffer_delete(_null_buf);
        } else {
            show_debug_message("WARNING: " + _nullsid_path + " not found in Included Files!");
        }
    }

    return instruction_list;
}