function scr_c64_do_update_addresses() {

global.named_loc_repack_gen++;

// ================================================================
// PASS 0: SYNC SPRITE POINTER HW LOCATIONS TO ACTIVE VIC CONFIG
// ================================================================
scr_update_spr_ptr_hw_locs();

// ================================================================
// PASS 0.2: DETECT $01 BANK UNLOCKS FROM ACTUAL INSTRUCTIONS
// Sets global.basic_unlocked / global.kernal_unlocked from the real
// lda $01 / and #mask / sta $01 triplet so the memory bar reflects
// banking however it was authored (combined node, split, or typed).
// ================================================================
scr_detect_bank_unlock();
// ================================================================
// PASS 0.5: $0000 ORG SAFETY FLAG (informational only)
// Sets global.has_zero_org_crash so any build entry point can check
// and bail. The actual block lives in scr_compile_chain; this just
// keeps the flag fresh for UI/build code to consult.
// ================================================================
global.has_zero_org_crash = (array_length(scr_check_org_zero_crash()) > 0);
	// ================================================================
	// UV VARIABLE REPACK (Multi-ORG Support)
	// ================================================================
	var _var_orgs = [];
	with (obj_c64_node) {
	    if (node_type == "ORG" && node_title == "VARIABLES") {
	        array_push(_var_orgs, id);
	    }
	}

	for (var _vi = 0; _vi < array_length(_var_orgs); _vi++) {
	    var _this_org = _var_orgs[_vi];
		

		var _uv_nodes = [];
	    with (obj_c64_node) {
	        if (org_parent == _this_org && (node_type == "NAMED_LOC" || node_type == "NEW_STR")) {
	            array_push(_uv_nodes, id);
	        }
	    }
	    array_sort(_uv_nodes, function(a, b) { return a.y - b.y; });

	    var _next_addr = _this_org.pc_address;
	    for (var _i = 0; _i < array_length(_uv_nodes); _i++) {
	        var _n    = _uv_nodes[_i];
	        var _name = string(_n.instructions[0][1]);
	        var _size = 1;

if (_n.node_type == "NEW_STR") {
	            // Size = string length + 1 (null terminator), or asset buffer size
	            var _use_as = (array_length(_n.instructions[0]) > 4 && is_real(_n.instructions[0][4])) ? real(_n.instructions[0][4]) : 0;
	            if (_use_as == 1) {
	                var _asname = (array_length(_n.instructions[0]) > 5) ? string(_n.instructions[0][5]) : "";
	                _size = 1;
	                if (_asname != "" && instance_exists(obj_asset_manager)) {
	                    var _am = obj_asset_manager;
	                    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	                        var _a = ds_list_find_value(_am.asset_list, _ai);
	                        if (_a.type == "TEXT_DATA" && _a.name == _asname) {
	                           // _size = buffer_exists(_a.buffer) ? buffer_get_size(_a.buffer) : 1;
								_size = buffer_exists(_a.buffer) ? max(1, buffer_get_size(_a.buffer) - 2) : 1;
	                            break;
	                        }
	                    }
	                }
	            } else {
	                var _inl = (array_length(_n.instructions[0]) > 3) ? string(_n.instructions[0][3]) : "";
	                _size = string_length(_inl);// + 1; // +1 for null terminator
	            }
	            _n.total_node_size = _size;
	            _n.pc_address      = _next_addr;
	            _next_addr        += _size;
	            continue;
	        }

	        var _meta = scr_nloc_find_meta(_name);
	        show_debug_message("UV REPACK: name=" + _name + " meta_found=" + string(_meta != undefined)
	            + " map_has_key=" + string(ds_map_exists(global.named_loc_map, string_upper(_name))) + " next_addr=" + string(_next_addr));
	        if (_meta != undefined) {
				var _enc = variable_struct_exists(_meta, "encoding") ? _meta.encoding : "byte";
	            if (_enc == "bcd" || _enc == "bcd3")        _size = 3;
	            else if (_enc == "word" || _enc == "bcd2")  _size = 2;
	            else                                         _size = 1; // byte, sbyte, signed all = 1
	
	            _meta.addr = _next_addr;
	            ds_map_set(global.named_loc_map, string_upper(_name), _next_addr);
	        }
	        _n.pc_address = _next_addr;
	        _next_addr += _size;
	    }
	    _this_org.end_address = _next_addr;
	}

	// Meta Cleanup: remove stale UV entries that have no matching node
	var _clean_meta = [];
	for (var _i = 0; _i < array_length(global.named_loc_meta); _i++) {
	    var _m = global.named_loc_meta[_i];
	    var _node_exists = false;
		with (obj_c64_node) {
	        if ((node_type == "NAMED_LOC" || node_type == "NEW_STR") && string(instructions[0][1]) == _m.name) {
	            _node_exists = true;
	            break;
	        }
	    }
	    if (_m.type == "HW" || _node_exists) array_push(_clean_meta, _m);
	    else ds_map_delete(global.named_loc_map, string_upper(_m.name));
	}
	global.named_loc_meta = _clean_meta;
	global.named_loc_meta_dirty = true;

	// ================================================================
	// PASS 1: BINARY ASSET SIZING
	// ================================================================
	with (obj_c64_node) {
	    if (node_type == "DATA_SID" || node_type == "SPR64") {
	        if (variable_instance_exists(id, "sprite_buffer") && buffer_exists(sprite_buffer)) {
	            total_node_size = (node_type == "SPR64") ? 4096 : buffer_get_size(sprite_buffer);
	        }
	    }
	    if (node_type == "BITMAP_KLA") {
	        if (variable_instance_exists(id, "kla_buffer") && buffer_exists(kla_buffer)) {
	            total_node_size = 10001;
	        }
	    }

	    if (node_type == "MACRO_PRINT" && total_node_size == 0) {
	        var _txt = (array_length(instructions) > 0 && array_length(instructions[0]) > 4)
	                 ? string(instructions[0][4]) : "";
	        total_node_size = max(10, string_length(_txt) * 6 + 10);
	        node_cycles     = total_node_size * 4;
	    }
	}

with (obj_c64_node) {
	    if (node_type == "MACRO_CHR") {
	        if (array_length(instructions) == 1 && string(instructions[0][1]) != "") {
	            scr_macro_chr_sync(id);
	        }
	    }
	}

	// ================================================================
	// PASS 1.5: MACRO SIZING VIA COMPILE CHAIN
	// ================================================================
	with (obj_c64_node) {
	    if (string_pos("MACRO", node_type) > 0 ||
	        node_type == "GET_VAR" ||
	        node_type == "SET_VAR" ||
	        node_type == "INC_VAR" ||
	        node_type == "DEC_VAR" ||
	        node_type == "COPY_VAR" ||
	        node_type == "BANK_SWITCH"     ||

		   // update wiith inline byte data used for frames.
	        node_type == "MACRO_ANIM"      ||
	        node_type == "MACRO_COLLISION" ||
			node_type == "MACRO_COLL_ADV") {
	        
	            total_node_size = 0;
	            node_cycles     = 0;
	        
	    }
	}



with (obj_c64_node) {
    if (node_type == "MACRO_FLIP_X") {
        var _fx_count = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]))
                      ? real(instructions[0][2]) : 1;
        node_cycles = _fx_count * 2000;
      
    }
}

	global.compile_sizing_pass = true;
var _compiled = scr_compile_chain();
global.compile_sizing_pass = false;

// ---- SHOW CODE PANEL ----
// Hand this sizing pass straight to the floating listing. The panel never
// runs a compile of its own, so keeping it live costs one array walk here
// rather than a second full compile inside the Draw event.
scr_show_code_build(_compiled);
	
	for (var _ci = 0; _ci < array_length(_compiled); _ci++) {
	    var _entry = _compiled[_ci];
	    if (array_length(_entry) < 3) continue;

	    var _mnem   = string_lower(string(_entry[0]));
	    var _src_id = _entry[2];

	    if (_mnem == "org" || _mnem == "label" || _mnem == "comment" || _mnem == "") continue;
	    if (is_string(_src_id)) continue;
	    if (!instance_exists(_src_id)) continue;

	    _mnem = string_replace_all(_mnem, "_abs_x",   "_abx");
	    _mnem = string_replace_all(_mnem, "_abs_y",   "_aby");
	    _mnem = string_replace_all(_mnem, "_zp_x",    "_zpx");
	    _mnem = string_replace_all(_mnem, "_zp_y",    "_zpy");
	    _mnem = string_replace_all(_mnem, "_imm_rep", "_imm");
	if (_mnem == "jmp") _mnem = "jmp_abs";
    if (_mnem == "lda_lab_lo" || _mnem == "lda_lab_hi") _mnem = "lda_imm";
	if (_mnem == "byte_lab_lo" || _mnem == "byte_lab_hi") _mnem = "byte";
    if (_mnem == "lda_lab")  _mnem = "lda_abs";
    if (_mnem == "sta_lab")  _mnem = "sta_abs";
    if (_mnem == "inc_lab")  _mnem = "inc_abs";
    if (_mnem == "dec_lab")  _mnem = "dec_abs";
    if (_mnem == "ora_lab")  _mnem = "ora_abs";
    if (_mnem == "and_lab")  _mnem = "and_abs";
    if (_mnem == "cmp_lab")  _mnem = "cmp_abs";
    if (_mnem == "beq")      _mnem = "bne";
    if (_mnem == "bcc")      _mnem = "bcs";
    if (_mnem == "bpl")      _mnem = "bmi";
    if (_mnem == "bvc")      _mnem = "bvs";

    // Bytes genuinely detached by a .pc relocation are already tagged
    // noone by the compile chain and filtered out above via
    // instance_exists(_src_id) — no MACRO_CODE-specific rule needed here
    // anymore. (Previously this blanket-excluded ALL byte data for every
    // MACRO_CODE node regardless of relocation, silently undercounting
    // any inline data table protected by a JMP rather than an org.)
    if (!object_is_ancestor(_src_id.object_index, obj_c64_node) && _src_id.object_index != obj_c64_node) continue;

    if (_src_id.node_type == "COND_IF") continue;

    var _sz = obj_opCodeManager.get_size(_mnem);
    //if (_sz == 0) show_debug_message("MACRO SIZE ZERO: " + _mnem);
    _src_id.total_node_size += _sz;
    _src_id.node_cycles     += obj_opCodeManager.get_cycles(_mnem);
	}

	with (obj_c64_node) {
    if ((node_type == "MACRO_MAP" || node_type == "MACRO_VSCROLL") && total_node_size > 0 && node_cycles == 0) {
        node_cycles = 208;
    }

	if (node_type == "COND_IF_WORD") {
	    // ── 16-BIT COMPARE SIZING ─────────────────────────────────
	    // Must match the COND_IF_WORD emit pass byte-for-byte or every
	    // node after this one drifts. CMP/SBC abs = 3, imm = 2.
	    //
	    // eq:     LDA(3) CMP(2/3) BNE(2) LDA(3) CMP(2/3) BNE(2) JMP(3)  = 17 or 19
	    // ne:     same shape, extra label costs nothing               = 17 or 19
	    // lt/gte: LDA(3) SEC(1) SBC(2/3) LDA(3) SBC(2/3) Bxx(2) JMP(3) = 17 or 19
	    // gt/lte: equality block (15 or 17) + ordered block (17 or 19) = 32 or 36
	    var _cwif_cmp_name = "";
	    if (array_length(instructions[0]) > 5) {
	        _cwif_cmp_name = string(instructions[0][5]);
	    }
	    var _cwif_use_var = (_cwif_cmp_name != "" && _cwif_cmp_name != "0");
	    var _cwif_mode    = string(instructions[0][4]);

	    // +1 per abs operand over imm; two operands in simple forms,
	    // four in gt/lte (two in the equality test, two in the compare)
	    var _cwif_extra = 0;
	    if (_cwif_use_var) {
	        _cwif_extra = 1;
	    }

	    if (_cwif_mode == "gt" || _cwif_mode == "lte") {
	        total_node_size = 32 + (_cwif_extra * 4);
	        node_cycles     = 38;
	    } else {
	        total_node_size = 17 + (_cwif_extra * 2);
	        node_cycles     = 22;
	    }

	} else if (node_type == "COND_IF") {
	    var _cif_mode   = string(instructions[0][4]);
	    var _cif_target = string(instructions[0][3]);
	    var _cif_taddr  = 0;
	    var _cif_tfind  = _cif_target;
	    var _cif_same_org = false;
	    with (obj_c64_node) {
	        if (node_type == "LABEL" && string(instructions[0][1]) == _cif_tfind) {
	            _cif_taddr = pc_address;
	            if (other.org_parent != noone && org_parent == other.org_parent) {
	                _cif_same_org = true;
	            }
	            if (other.org_parent == noone && org_parent == noone) {
	                _cif_same_org = true;
	            }
	            break;
	        }
	    }
	    var _cif_offset   = _cif_taddr - (pc_address + 5);
	    var _cif_in_range = (_cif_taddr != 0) && (_cif_offset >= -128 && _cif_offset <= 127);
	    var _cif_forced   = (_cif_mode == "gt" || _cif_mode == "lte");
	    // Compare-against-variable detection. The emit pass (_walk_spine COND_IF)
	    // uses CMP abs (3 bytes) when comparing to another named var, but CMP imm
	    // (2 bytes) when comparing to a literal. Sizing here must match, or every
	    // node after a var-vs-var IF drifts 1 byte and silently collides.
	    var _cif_cmp_name = (array_length(instructions[0]) > 5) ? string(instructions[0][5]) : "";
	    var _cif_cmp_addr = 0;
	    if (_cif_cmp_name != "" && _cif_cmp_name != "0") {
	        if (ds_map_exists(global.named_loc_map, _cif_cmp_name)) {
	            _cif_cmp_addr = ds_map_find_value(global.named_loc_map, _cif_cmp_name);
	        }
	        if (_cif_cmp_addr == 0) {
	            var _cif_cmp_find = _cif_cmp_name;
	            with (obj_c64_node) {
	                if (node_type == "NAMED_LOC" && string(instructions[0][1]) == _cif_cmp_find) {
	                    other._cif_cmp_addr = pc_address;
	                    break;
	                }
	            }
	        }
	    }
	    var _cif_is_var_cmp = (_cif_cmp_name != "" && _cif_cmp_name != "0" && _cif_cmp_addr != 0);
	    var _cif_cmp_extra  = 0;
	    if (_cif_is_var_cmp) {
	        _cif_cmp_extra = 1; // CMP abs is 1 byte larger than CMP imm
	    } else {
	        _cif_cmp_extra = 0;
	    }
	    // Force long (springboard) form everywhere so sizing always matches
	    // the emit pass below. Short-branch collapse is disabled to keep node
	    // addresses truthful (no 3-byte over-reservation / BRK padding drift).
	    _cif_in_range = false;
	    if (_cif_in_range && !_cif_forced) {
	        total_node_size = 7 + _cif_cmp_extra;
	        node_cycles     = 9;
	    } else if (_cif_forced) {
		    if (_cif_mode == "gt") {
		        // BEQ skip(2) + BCC skip(2) + JMP target(3) = 12, plus CMP abs delta
		        total_node_size = 12 + _cif_cmp_extra;
		        node_cycles     = 15;
		    } else {
		        // lte: BEQ target(2) + BCC target(2) + JMP skip(3) = 12, plus CMP abs delta
		        total_node_size = 12 + _cif_cmp_extra;
		        node_cycles     = 15;
		    }
		} else {
	        total_node_size = 10 + _cif_cmp_extra;
	        node_cycles     = 13;
	    }
	}
}

// ================================================================
// PASS 1.75: MACRO_SID AUTO-LINK TO NEAREST DATA_SID (legacy only)
// ================================================================
with (obj_c64_node) {
    if (node_type == "MACRO_SID") {
        sid_link = noone;
    }
}

	// ================================================================
	// PASS 2: SIZE CALCULATION (Instructions, Data)
	// ================================================================
	with (obj_c64_node) {
	    var _final_bytes  = 0;
	    var _final_cycles = 0;

	    if (node_type == "NORMAL" || node_type == "INIT" || node_type == "BRANCH") {
	        for (var j = 0; j < array_length(instructions); j++) {
	            var _ins = string_lower(string(instructions[j][0]));
	            if (_ins == "label" || _ins == "comment" || _ins == "") continue;
	            if (_ins == "jmp") _ins = "jmp_abs";
	            _ins = string_replace_all(_ins, "_abs_x",   "_abx");
	            _ins = string_replace_all(_ins, "_abs_y",   "_aby");
	            _ins = string_replace_all(_ins, "_zp_x",    "_zpx");
	            _ins = string_replace_all(_ins, "_zp_y",    "_zpy");
	            _ins = string_replace_all(_ins, "_imm_rep", "_imm");
	            _final_bytes  += obj_opCodeManager.get_size(_ins);
	            _final_cycles += obj_opCodeManager.get_cycles(_ins);
	        }
	        total_node_size = _final_bytes;
	        node_cycles     = _final_cycles;
	    } else if (node_type == "RAW_DATA") {
	        var _raw = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
	        if (_raw != "") total_node_size = array_length(string_split(_raw, ","));
	    } else if (node_type == "DATA_TEXT") {
	        var _total_t = 0;
	        for (var _ti = 0; _ti < array_length(instructions); _ti++) {
	            _total_t += string_length(string(instructions[_ti][1]));
	        }
	        total_node_size = _total_t;
	    }
	}

	// ================================================================
	// PASS 3: ADDRESS ASSIGNMENT - MAIN SPINE (no ORG parent)
	// ================================================================
	var _current_pc = global.start_pc;
	var _main_spine = [];

	with (obj_c64_node) {
	    if (is_connected && x > 160 && org_parent == noone && node_type != "ORG") {
	        array_push(_main_spine, id);
	    }
	}
	array_sort(_main_spine, function(_a, _b) { 
		var _diff = _a.y - _b.y;
		if (_diff == 0) return (_a.id > _b.id) ? 1 : ((_a.id < _b.id) ? -1 : 0); // Tie-breaker for stability
		return _diff; 
	});

var _G = 20;
	var _running_cycles = 0;
	var _pack_y = (array_length(_main_spine) > 0) ? _main_spine[0].y : 60;
	_pack_y = ceil(_pack_y / _G) * _G;
	for (var i = 0; i < array_length(_main_spine); i++) {
	    var _n    = _main_spine[i];
	    _n.y      = _pack_y;
	    _n.height = ceil(_n.height / _G) * _G;
	    _pack_y  += _n.height;
/*
	    if (_n.node_type == "ORG") {
	        if (!variable_instance_exists(_n, "proxy")) _n.proxy = true;
	        if (_n.proxy) _n.pc_address = _current_pc;
	        _current_pc = _n.pc_address;
	    }
		*/
if (_n.node_type == "ORG") {
            _n.is_draggable = true;
            _n.is_connected = false;
            _n.proxy        = variable_instance_exists(_n, "proxy") ? _n.proxy : false;
        }

	    _n.pc_address  = _current_pc;
	    _n.end_address = _current_pc + _n.total_node_size;

	    _running_cycles        += variable_instance_exists(_n, "node_cycles") ? _n.node_cycles : 0;
	    _n.cumulative_scanlines = _running_cycles / 63;

	    var _hex = decimal_to_hex(_n.pc_address);
	    while (string_length(_hex) < 4) _hex = "0" + _hex;
	    _n.display_address = "$" + string_upper(_hex);

	    _current_pc = _n.end_address;
	}

	// ================================================================
	// PASS 4: ADDRESS ASSIGNMENT - ORG CHILD CHAINS
	// ================================================================
	with (obj_c64_node) {
	    if (node_type == "ORG") {
	        var _org_anchor  = id;
	        var _chain_pc    = pc_address;
	        var _chain_cycles = 0;

	        // Inherit cumulative cycles from nearest spine column to the left.
	        // EXCEPTION: a hard-addressed ORG (proxy OFF, no wire input) is a
	        // deliberate absolute placement and a fresh timing origin — it has
	        // no meaningful spatial predecessor, so seed its chain from 0.
	        // (Jumped-to hard ORGs are re-seeded correctly by Pass 4.25.)
        var _p4_is_hard = (!_org_anchor.proxy && _org_anchor.wire_in_source == -1);
        var _best_cycles_end = 0;
        var _best_cycles_x   = -999999;
        if (!_p4_is_hard) {
            with (obj_c64_node) {
                if (id == _org_anchor) continue;
                if (x >= _org_anchor.x) continue;
                if (!is_connected && org_parent == noone) continue;
                if (variable_instance_exists(id, "cumulative_scanlines")) {
                    var _this_cycles = cumulative_scanlines * 63;
                    if (x > _best_cycles_x) {
                        _best_cycles_x   = x;
                        _best_cycles_end = _this_cycles;
                    }
                }
            }
        }
        _chain_cycles = _best_cycles_end;

        // OVERLAP REBASE: if this ORG physically overwrites an earlier block's
        // bytes (its pc_address lands inside another connected block's range),
        // the overwritten cycles never actually run at runtime — rebase the
        // chain to the cycle count AT the overlap entry point, not after it.
        if (_org_anchor.node_title != "VARIABLES" && _org_anchor.node_title != "HW REGISTERS") {
            var _org_pc = _org_anchor.pc_address;
            with (obj_c64_node) {
                if (id == _org_anchor) continue;
                if (!is_connected) continue;
                if (node_type == "ORG") continue;
                if (node_type == "NAMED_LOC" || node_type == "NEW_STR") continue;
                if (total_node_size <= 0) continue;
                if (_org_pc >= pc_address && _org_pc < pc_address + total_node_size) {
                    // ORG lands inside this block — credit only the cycles up to entry
                    if (variable_instance_exists(id, "cumulative_scanlines")) {
                        var _block_end_cyc   = cumulative_scanlines * 63;
                        var _block_self_cyc  = variable_instance_exists(id, "node_cycles") ? node_cycles : 0;
                        var _block_start_cyc = _block_end_cyc - _block_self_cyc;
                        // Best-effort: drop the overwritten block's contribution
                        _chain_cycles = _block_start_cyc;
                    }
                }
            }
        }

	        var _org_list = [];
	        with (obj_c64_node) {
	            if (org_parent == _org_anchor) array_push(_org_list, id);
	        }
	        array_sort(_org_list, function(_a, _b) { return _a.y - _b.y; });

	        var _child_y = _org_anchor.y + _org_anchor.height;
	        for (var k = 0; k < array_length(_org_list); k++) {
	            var _child = _org_list[k];

	            _child.x  = _org_anchor.x;
	            _child.y  = _child_y;
	            _child_y += _child.height;

	            if (_child.node_type == "NAMED_LOC" || _child.node_type == "NEW_STR") continue;

	            _child.pc_address  = _chain_pc;
	            _child.end_address = _chain_pc + _child.total_node_size;

	            _chain_cycles              += variable_instance_exists(_child, "node_cycles") ? _child.node_cycles : 0;
	            _child.cumulative_scanlines = _chain_cycles / 63;

	            var _chex = decimal_to_hex(_child.pc_address);
	            while (string_length(_chex) < 4) _chex = "0" + _chex;
	            _child.display_address = "$" + string_upper(_chex);

	            _chain_pc = _child.end_address;
	        }

	        // Update ORG end_address (VARIABLES is handled by UV repack)
	        if (_org_anchor.node_title != "VARIABLES") {
	            var _org_end = _org_anchor.pc_address;
	            with (obj_c64_node) {
	                if (org_parent == _org_anchor && is_connected && node_type != "NAMED_LOC") {
	                    var _e = pc_address + total_node_size;
	                    if (_e > _org_end) _org_end = _e;
	                }
	            }
	            _org_anchor.end_address = _org_end;
	        }
	    }
	}

	
// ================================================================
	// PASS 4.25: JMP-TARGET CYCLE INHERITANCE (cycles only, no PC changes)
	// For any ORG whose first LABEL child is the target of a JMP/JSR, re-seed
	// the cumulative cycle count from that jumper and re-walk ONLY the children's
	// cumulative_scanlines. Addresses, sizes and end_address are left untouched.
	// ================================================================
	with (obj_c64_node) {
	    if (node_type != "ORG") continue;
	    if (node_title == "VARIABLES" || node_title == "HW REGISTERS") continue;
	    var _ci_org = id;

	    // First LABEL child's name (lives in instructions[0][1])
	    var _ci_label = "";
	    var _ci_ly    = 1000000000;
	    with (obj_c64_node) {
	        if (org_parent != _ci_org) continue;
	        if (node_type != "LABEL") continue;
	        if (y < _ci_ly && array_length(instructions) > 0 && array_length(instructions[0]) > 1
	            && is_string(instructions[0][1])) {
	            _ci_ly = y;
	            _ci_label = string_upper(string(instructions[0][1]));
	        }
	    }
	    if (_ci_label == "" || _ci_label == "TARGET" || _ci_label == "LABEL") continue;

	    // Find the rightmost jumper targeting that label; take its cumulative cycles
	    var _ci_best_cyc = -1;
	    var _ci_best_x   = -999999;
	    with (obj_c64_node) {
	        if (id == _ci_org) continue;
	        if (org_parent == _ci_org) continue;
	        if (!variable_instance_exists(id, "instructions")) continue;
	        var _ci_match = false;
	        for (var _cji = 0; _cji < array_length(instructions); _cji++) {
	            if (array_length(instructions[_cji]) < 2) continue;
	            var _cjm = string_lower(string(instructions[_cji][0]));
	            if (_cjm != "jmp" && _cjm != "jmp_abs" && _cjm != "jsr") continue;
	            if (is_string(instructions[_cji][1])
	                && string_upper(string(instructions[_cji][1])) == _ci_label) {
	                _ci_match = true; break;
	            }
	        }
	        if (_ci_match && variable_instance_exists(id, "cumulative_scanlines") && x > _ci_best_x) {
	            _ci_best_x   = x;
	            _ci_best_cyc = cumulative_scanlines * 63;
	        }
	    }
	    if (_ci_best_cyc < 0) continue; // no jumper — leave Pass 4's spatial seed as-is

	    // Re-walk children: cumulative_scanlines ONLY. Do not touch pc/end/size.
	    var _ci_list = [];
	    with (obj_c64_node) {
	        if (org_parent == _ci_org) array_push(_ci_list, id);
	    }
	    array_sort(_ci_list, function(_a, _b) { return _a.y - _b.y; });

	    var _ci_chain = _ci_best_cyc;
	    for (var _cik = 0; _cik < array_length(_ci_list); _cik++) {
	        var _cc = _ci_list[_cik];
	        if (_cc.node_type == "NAMED_LOC" || _cc.node_type == "NEW_STR") continue;
	        _ci_chain               += variable_instance_exists(_cc, "node_cycles") ? _cc.node_cycles : 0;
	        _cc.cumulative_scanlines = _ci_chain / 63;
	    }
	    _ci_org.inherited_cycles = _ci_best_cyc;
	}	
	
	
	
	// ================================================================
	// PASS 3.5: ORG PROXY INHERITANCE
	// Must run AFTER Pass 4 so all ORG end_addresses include children.
	// Picks the nearest column to the left (highest x < org.x) as the
	// upstream block, then re-walks children with the corrected pc_address.
	// ================================================================
// Ensure all ORG nodes have a stable UID (catches old saves that predate the wire system)
	with (obj_c64_node) {
	    if (node_type == "ORG" && org_uid == -1) {
	        org_uid = global.next_org_uid;
	        global.next_org_uid += 1;
	    }
	}

var _org_proxy_list = [];
	with (obj_c64_node) {
	    if (node_type == "ORG" && node_title != "VARIABLES" && node_title != "HW REGISTERS") {
	        var _has_proxy = variable_instance_exists(id, "proxy") && proxy;
	        var _has_wire  = wire_in_source != -1;
	        // Jumped-to (non-proxy) ORGs get their cycle inheritance from Pass 4.25,
	        // which never touches addresses. They must NOT enter Pass 3.5 (PC reassignment).
	        if (_has_proxy || _has_wire) {
	            array_push(_org_proxy_list, id);
	        }
	    }
	}
array_sort(_org_proxy_list, function(_a, _b) { return _a.y - _b.y; });

// Multi-pass stabilisation — worst case is one pass per ORG in the chain
	var _pass_max     = max(1, array_length(_org_proxy_list));
	var _pass_changed = true;

	for (var _pass = 0; _pass < _pass_max && _pass_changed; _pass++) {
	    _pass_changed = false;

for (var _oi = 0; _oi < array_length(_org_proxy_list); _oi++) {
    var _org           = _org_proxy_list[_oi];
    var _best_end      = global.start_pc;
    var _best_x        = -999999;
    var _best_found    = false;
    var _best_cycles_in = 0;
    var _pc_before     = _org.pc_address;
		
	    // ================================================================
	    // WIRE OVERRIDE: if this ORG has a direct wire input, use that
	    // source's end_address and skip the zone search entirely
	    // ================================================================
	    if (_org.wire_in_source != -1) {
	        var _wire_resolved = false;
	        with (obj_c64_node) {
	            if (node_type == "ORG" && org_uid == _org.wire_in_source) {
	                _org.pc_address = end_address;
	                var _wire_hex = decimal_to_hex(_org.pc_address);
	                while (string_length(_wire_hex) < 4) _wire_hex = "0" + _wire_hex;
	                _org.display_address = "$" + string_upper(_wire_hex);
	                _wire_resolved = true;
	                break;
	            }
	        }
	        if (_wire_resolved) {
	            // Re-walk children with the wired address
	            var _wire_anchor = _org;
	            var _wire_pc     = _org.pc_address;
	            var _wire_list   = [];
	            with (obj_c64_node) {
	                if (org_parent == _wire_anchor) array_push(_wire_list, id);
	            }
	            array_sort(_wire_list, function(_a, _b) { return _a.y - _b.y; });

	            // Inherit cumulative cycles from the wired source ORG.
	            // The ORG header itself never receives cumulative_scanlines
	            // (only its children do), so resolve the source chain's true
	            // end-of-block cycle total from its LOWEST connected child —
	            // mirroring the zone-search proxy path. Falls back to the
	            // header's own value (covers a childless source ORG).
	            var _wire_chain_cycles = 0;
	            var _wire_src_org      = noone;
	            with (obj_c64_node) {
	                if (node_type == "ORG" && org_uid == _wire_anchor.wire_in_source) {
	                    _wire_src_org = id;
	                    break;
	                }
	            }
	            if (instance_exists(_wire_src_org)) {
	                // Seed from the source ORG header (childless-source fallback)
	                _wire_chain_cycles = variable_instance_exists(_wire_src_org, "cumulative_scanlines")
	                                   ? (_wire_src_org.cumulative_scanlines * 63) : 0;
	                // Then prefer the lowest connected child's cumulative total
	                var _wsrc_lowest_y = _wire_src_org.y;
	                with (obj_c64_node) {
	                    if (org_parent != _wire_src_org) continue;
	                    if (!is_connected) continue;
	                    if (node_type == "NAMED_LOC" || node_type == "NEW_STR") continue;
	                    if (y > _wsrc_lowest_y && variable_instance_exists(id, "cumulative_scanlines")) {
	                        _wsrc_lowest_y     = y;
	                        _wire_chain_cycles = cumulative_scanlines * 63;
	                    }
	                }
	            }

	            for (var _wk = 0; _wk < array_length(_wire_list); _wk++) {
	                var _wchild = _wire_list[_wk];
	                if (_wchild.node_type == "NAMED_LOC" || _wchild.node_type == "NEW_STR") continue;
	                _wchild.pc_address  = _wire_pc;
	                _wchild.end_address = _wire_pc + _wchild.total_node_size;
	                var _whex = decimal_to_hex(_wchild.pc_address);
	                while (string_length(_whex) < 4) _whex = "0" + _whex;
	                _wchild.display_address = "$" + string_upper(_whex);

	                _wire_chain_cycles            += variable_instance_exists(_wchild, "node_cycles") ? _wchild.node_cycles : 0;
	                _wchild.cumulative_scanlines   = _wire_chain_cycles / 63;

	                _wire_pc = _wchild.end_address;
	            }
	            var _wire_end = _org.pc_address;
	            with (obj_c64_node) {
	                if (org_parent == _wire_anchor && is_connected && node_type != "NAMED_LOC") {
	                    var _we = pc_address + total_node_size;
	                    if (_we > _wire_end) _wire_end = _we;
	                }
	            }
	            _wire_anchor.end_address = _wire_end;
	            continue; // skip zone search for this ORG
	        }
	        // Source not found — wire is broken, clear it
	        _org.wire_in_source = -1;
	    }

// Purple zone — must match draw event exactly

	    var _zone_x1 = _org.x - (global.node_display_width * 3);
	    var _zone_x2 = _org.x + global.node_display_width;
	    var _zone_y1 = _org.y - 220; //  above: spine may start higher than our ORG
	    var _zone_y2 = _org.y + 100;                  // only look upward — nothing below our own Y

	    with (obj_c64_node) {
	        if (id == _org) continue;
	        if (x < _zone_x1 || x >= _zone_x2) continue;
	        if (y < _zone_y1 || y > _zone_y2) continue;

	        // Ask this witness: "who's your daddy?"
	        // If it has an org_parent, that parent owns the chain we want to measure
	        // If it has no parent and is INIT/ORG, it IS the chain root
	        var _daddy = noone;
	        if (org_parent != noone) {
	            _daddy = org_parent;
	        } else if (node_type == "INIT" || node_type == "ORG") {
	            if (node_title != "VARIABLES" && node_title != "HW REGISTERS") {
	                _daddy = id;
	            }
	        }
	        if (_daddy == noone) continue;
	        // Never measure our own family
	        if (_daddy == _org) continue;
	        if (org_parent == _org) continue;

	        // Walk daddy's children to find the lowest connected node and its end address
	        var _candidate_x  = _daddy.x;
	        var _spine_end    = variable_instance_exists(_daddy, "end_address") ? _daddy.end_address : global.start_pc;
	        var _lowest_y     = _daddy.y;
	        var _daddy_is_init = (_daddy.node_type == "INIT");

	        // Track the cumulative cycles of that same lowest node so ORG can continue from it.
	        // Default to daddy's own cycles in case it has no children (bare INIT/ORG root).
	        var _spine_cyc = variable_instance_exists(_daddy, "cumulative_scanlines") ? (_daddy.cumulative_scanlines * 63) : 0;

	        with (obj_c64_node) {
	            if (id == _daddy) continue;
	            if (!is_connected) continue;
	            if (node_type == "NAMED_LOC" || node_type == "NEW_STR") continue;
	            // INIT spine: children sit on same x with org_parent == noone
	            // ORG chain: children have org_parent == _daddy
	            if (_daddy_is_init) {
	                if (x != _daddy.x) continue;
	                if (org_parent != noone) continue;
	                if (node_type == "ORG") continue;
	            } else {
	                if (org_parent != _daddy) continue;
	            }
	            if (y > _lowest_y) {
	                _lowest_y  = y;
	                _spine_end = pc_address + total_node_size;
	                _spine_cyc = variable_instance_exists(id, "cumulative_scanlines") ? (cumulative_scanlines * 63) : 0;
	            }
	        }



	        // Rightmost daddy column wins, highest end breaks ties
        if (_candidate_x > _best_x) {
            _best_x         = _candidate_x;
            _best_end       = _spine_end;
            _best_cycles_in = _spine_cyc;
            _best_found     = true;
        } else if (_candidate_x == _best_x) {
            if (_spine_end > _best_end) {
                _best_end       = _spine_end;
                _best_cycles_in = _spine_cyc;
            }
            _best_found = true;
        }
	}
		
///////////////////////////////////////////////////
	    var _pc_before = _org.pc_address;

	    if (_org.proxy) {
	        if (!_best_found) {
	            _org.pc_address      = -1;
	            _org.display_address = "$----";
	        } else {
	            _org.pc_address = _best_end;
	        }
	    } else {
	        _org.pc_address = _org.proxy_address;
	    }

	    if (_org.pc_address != _pc_before) {
	        _pass_changed = true;
	    }

	    // Re-walk children with corrected pc_address
	    var _org_anchor = _org;
	    var _chain_pc   = _org.pc_address;
	    var _org_list   = [];
	    with (obj_c64_node) {
	        if (org_parent == _org_anchor) array_push(_org_list, id);
	    }
	    array_sort(_org_list, function(_a, _b) { return _a.y - _b.y; });

	    // ----------------------------------------------------------------
	    // CYCLE PREDECESSOR RESOLUTION (carried on the ORG itself)
	    // The ORG is the entry point jumped to, so we resolve the predecessor
	    // cycle total ONCE and store it on the ORG. Children then seed from it.
	    //
	    // HARD-ADDRESSED RESET: an ORG with proxy OFF and no wire input is a
	    // deliberate absolute placement (.org $XXXX) — a fresh timing origin.
	    // It has no meaningful predecessor to inherit from, so its chain seeds
	    // from 0. Jumped-to hard ORGs still get corrected by Pass 4.25.
	    // ----------------------------------------------------------------
	    var _is_hard_addr  = (!_org.proxy && _org.wire_in_source == -1);
	    var _chain_cycles  = _is_hard_addr ? 0 : (_best_found ? _best_cycles_in : 0);

// Cycle seed comes from the zone-search predecessor (_best_cycles_in).
	    // Jumped-to non-proxy ORGs are handled separately in Pass 4.25.

	    for (var _k = 0; _k < array_length(_org_list); _k++) {
	        var _child = _org_list[_k];
			if (_child.node_type == "NAMED_LOC" || _child.node_type == "NEW_STR") continue;
	        _child.pc_address  = _chain_pc;
	        _child.end_address = _chain_pc + _child.total_node_size;
	        var _chex = decimal_to_hex(_child.pc_address);
	        while (string_length(_chex) < 4) _chex = "0" + _chex;
	        _child.display_address = "$" + string_upper(_chex);

	        _chain_cycles              += variable_instance_exists(_child, "node_cycles") ? _child.node_cycles : 0;
	        _child.cumulative_scanlines = _chain_cycles / 63;

	        _chain_pc = _child.end_address;
	    }
	    var _org_end = _org.pc_address;
	    with (obj_c64_node) {
	        if (org_parent == _org_anchor && is_connected && node_type != "NAMED_LOC") {
	            var _e = pc_address + total_node_size;
	            if (_e > _org_end) _org_end = _e;
	        }
	    }
	    _org_anchor.end_address = _org_end;
	}

	} // end multi-pass stabilisation loop

	// ================================================================
	// PASS 5: LABEL RESOLUTION
	// ================================================================
	with (obj_c64_node) {
	    if (!variable_instance_exists(id, "instructions")) continue;
	    if (array_length(instructions) == 0) continue;

	    for (var i = 0; i < array_length(instructions); i++) {
	        if (array_length(instructions[i]) < 2) continue;

	        var _mnem = string_lower(string(instructions[i][0]));
	        var _val  = instructions[i][1];

	        if (!is_string(_val) || _val == "" || _val == "BIN_DATA_ACTIVE") continue;

	        var _target_label = string_upper(_val);
	        var _found_addr   = -1;

	        with (obj_c64_node) {
	            if (string_upper(node_title) == _target_label) {
	                _found_addr = pc_address;
	            }
	        }

	        if (_found_addr == -1) continue;

	        // Absolute jumps and calls (16-bit operand)
	        if (_mnem == "jsr" || _mnem == "jmp_abs" || _mnem == "jmp_ind" || _mnem == "jmp") {
	            instructions[i][2] = _found_addr;
	        }

	        // Relative branches (8-bit signed offset)
	        if (string_char_at(_mnem, 1) == "b" && string_length(_mnem) == 3) {
	            var _dist = _found_addr - (pc_address + 2);
	            instructions[i][2] = _dist;
	            if (_dist < -128 || _dist > 127) {
	                show_debug_message("WARNING: Branch '" + _target_label + "' out of range at $"
	                                   + string_upper(decimal_to_hex(pc_address)));
	            }
	        }
	    }
	}
// Force overlap re-evaluation after address update
	with (obj_c64_node) { 
	    last_overlap_check = false; 
	    overlap_check_dirty = true;
	    stats_cache_dirty   = true; // rebuild cycle/byte stats strings with fresh cumulative_scanlines
	    if (node_type == "MACRO_CODE") code_cache_dirty = true;
	}
	
	// ================================================================
	// PASS 6: GLOBAL CONFLICT DETECTION (Source of Truth)
	// ================================================================
	global.conflict_ranges      = [];
	global.memory_bar_segments   = [];
    global.memory_bar_conflicts  = [];
    global.memory_bar_disk_assets = [];
	global.memory_bar_dirty     = true;
	var _segs = [];

	// SAFETY NET: ensure ORG children inherit the connected state of their
	// parent ORG, otherwise they won't enter the conflict pool and will
	// silently overwrite spine bytes without flashing.
	with (obj_c64_node) {
	    if (org_parent != noone && instance_exists(org_parent)) {
	        if (org_parent.is_connected) {
	            is_connected = true;
	        }
	    }
	}

// Collect segments from all nodes
	with (obj_c64_node) {
	    is_conflicted = false; // Reset first
	    
	    // Check if this specific node is currently being clicked but hasn't started dragging
	    var _is_being_clicked = false;
	    if (mouse_check_button(mb_left) && !is_dragging) {
	        var _draw_x = x + x_indent; // Match your render script bounds
	        if (point_in_rectangle(mouse_x, mouse_y, _draw_x, y, _draw_x + width, y + height)) {
	            _is_being_clicked = true;
	        }
	    }

	    // Treat ORG children as connected for collision purposes even if their flag
	    // hasn't been refreshed (the parent ORG owns the chain's connection state)
	    var _effective_connected = is_connected;
	    if (!_effective_connected && org_parent != noone && instance_exists(org_parent)) {
	        if (org_parent.is_connected) _effective_connected = true;
	    }

	    // CRITICAL FIX: Only check connected nodes! 
	    // Disconnected nodes hold ghost addresses and must be excluded from the collision pool.
	    if (total_node_size > 0 && _effective_connected && !is_dragging && !_is_being_clicked) {
	        array_push(_segs, { start: pc_address, finish: pc_address + total_node_size, owner: id });
	    }
	}
	
// Collect segments from assets
	// First build a set of asset names that are linked to any LOAD_ORG
	var _load_org_linked = ds_map_create();
	    if (instance_exists(obj_asset_manager)) {
	        var _am_lo = obj_asset_manager;
	        for (var _loi = 0; _loi < ds_list_size(_am_lo.asset_list); _loi++) {
	            var _loa = ds_list_find_value(_am_lo.asset_list, _loi);
	            if (_loa.type != "LOAD_ORG" && _loa.type != "LOAD_REU") continue;
	            if (!variable_struct_exists(_loa, "linked_assets")) continue;
	            for (var _loli = 0; _loli < array_length(_loa.linked_assets); _loli++) {
	                var _lolink = _loa.linked_assets[_loli];
	                if (variable_struct_exists(_lolink, "asset_name") && _lolink.asset_name != "") {
	                    ds_map_replace(_load_org_linked, _lolink.asset_name, true);
	                }
	            }
	        }
	    }
	if (instance_exists(obj_asset_manager)) {
	    var _am = obj_asset_manager;
	    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	        var _a = _am.asset_list[| _ai];
	        // Skip assets marked load_later via any LOAD_ORG
	        if (ds_map_exists(_load_org_linked, _a.name)) continue;
	        // BITMAP is not one contiguous span — it's three separate regions,
	        // and in VIC bank 2 they aren't even adjacent (bitmap $8000, colour
	        // $9F40, screen way up at $BC00). A flat 10192 from the base both
	        // over-claims the gap between them and completely misses the screen
	        // block, so a node writing into screen RAM never flagged while
	        // phantom conflicts fired against empty space. Push one segment per
	        // real region — all under the same asset name, so the name-match
	        // rule in the conflict pass keeps them from flagging each other.
	        if (_a.type == "BITMAP") {
	            if (_a.file != "" && buffer_exists(_a.buffer)) {
	                var _p6_br = scr_bmp_regions(_a.address);
	                array_push(_segs, { start: _p6_br.bmp_addr, finish: _p6_br.bmp_addr + _p6_br.bmp_size, owner: noone, name: _a.name });
	                array_push(_segs, { start: _p6_br.scr_addr, finish: _p6_br.scr_addr + _p6_br.scr_size, owner: noone, name: _a.name });
	                array_push(_segs, { start: _p6_br.col_addr, finish: _p6_br.col_addr + _p6_br.col_size, owner: noone, name: _a.name });
	            }
	            continue;
	        }

	        var _asz = 0;
	        if (_a.type == "SPRITE_SET") _asz = buffer_exists(_a.buffer) ? buffer_get_size(_a.buffer)-2 : 0;
	        if (_a.type == "SID_MUSIC") _asz = buffer_exists(_a.buffer) ? buffer_get_size(_a.buffer)-2 : 0;
	        if (_asz > 0) array_push(_segs, { start: _a.address, finish: _a.address + _asz, owner: noone, name: _a.name });
	    }
	}
	ds_map_destroy(_load_org_linked);

// Collect const proxy segments from MACRO_CODE nodes
	with (obj_c64_node) {
	    if (node_type != "MACRO_CODE") continue;
	    if (!is_connected) continue;
	    if (!variable_instance_exists(id, "code_seg_cache")) continue;
	    for (var _sci = 0; _sci < array_length(code_seg_cache); _sci++) {
	        var _cs = code_seg_cache[_sci];
	        if (_cs.size > 0) {
	            array_push(_segs, { start: _cs.addr, finish: _cs.addr + _cs.size, owner: id, node_id: id });
	        }
	    }
	}

// Sort and Detect (full pairwise)
	array_sort(_segs, function(a, b) { return a.start - b.start; });

	for (var i = 0; i < array_length(_segs); i++) {
		for (var j = i + 1; j < array_length(_segs); j++) {
	        var s1 = _segs[i];
	        var s2 = _segs[j];
if (s1.finish <= s2.start) break;
	        if (s1.owner != noone && s1.owner == s2.owner) continue;
	        if (variable_struct_exists(s1, "node_id") && variable_struct_exists(s2, "node_id") && s1.node_id == s2.node_id) continue;
	        var _c_start = max(s1.start, s2.start);
	        var _c_end   = min(s1.finish, s2.finish);

	        // --- SHARED RESOURCE EXCEPTION ---
	        var _is_shared = false;
	        if (_c_start <= 0x03FF) _is_shared = true; // ZP, Stack, OS
	        else if (_c_start >= 0x0400 && _c_start <= 0x07FF) _is_shared = true; // Screen RAM + buf 2
	        else if (_c_start >= 0xD000 && _c_start <= 0xDFFF) _is_shared = true; // HW Regs
	        // Sprite pointer tables: last 8 bytes of any 1K screen block within any VIC bank
	        else {
	            var _screen_block_offset = _c_start & 0x03FF;
	            if (_screen_block_offset >= 0x03F8 && _screen_block_offset <= 0x03FF) _is_shared = true;
	        }
	        // Assets vs MACRO_CODE nodes: MACRO_CODE executes from spine PC, not the asset range
	        // The physical code bytes don't live inside the asset — suppress this false positive
	        if (!_is_shared) {
	            var _s1_is_code = instance_exists(s1.owner) && s1.owner.node_type == "MACRO_CODE";
	            var _s2_is_code = instance_exists(s2.owner) && s2.owner.node_type == "MACRO_CODE";
	            var _s1_is_asset = !instance_exists(s1.owner); // assets have owner=noone
	            var _s2_is_asset = !instance_exists(s2.owner);
	            if ((_s1_is_code && _s2_is_asset) || (_s2_is_code && _s1_is_asset)) _is_shared = true;
	        }

	        if (_is_shared) continue;

	        // Honour user-ignored conflicts
	        if (scr_is_conflict_ignored(_c_start, _c_end, s1.owner, s2.owner)) continue;

	        array_push(global.conflict_ranges, { addr_start: _c_start, addr_end: _c_end });
	        // Six separate passes in this script can set is_conflicted, so a red
	        // node on its own says nothing about which one fired. Name the pair
	        // and the range here; the operand passes below log their own.
	        show_debug_message("CONFLICT PASS 6: $" + string_upper(decimal_to_hex(_c_start))
	            + "-$" + string_upper(decimal_to_hex(_c_end)) + "  "
	            + (instance_exists(s1.owner) ? string(s1.owner.node_type) + "#" + string(s1.owner) : "ASSET " + (variable_struct_exists(s1, "name") ? string(s1.name) : "?"))
	            + "  vs  "
	            + (instance_exists(s2.owner) ? string(s2.owner.node_type) + "#" + string(s2.owner) : "ASSET " + (variable_struct_exists(s2, "name") ? string(s2.name) : "?")));
	        if (instance_exists(s1.owner)) s1.owner.is_conflicted = true;
	        if (instance_exists(s2.owner)) s2.owner.is_conflicted = true;
	    }
	}
	
	// TEXT SCROLL string buffer conflict injection
with (obj_c64_node) {
    if (node_type != "MACRO_TEXT_SCROLL") continue;
    if (!is_connected) continue;
    if (array_length(instructions[0]) <= 6) continue;
    var _ts_taddr = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0xC000;
    var _ts_tlen  = string_length(string(instructions[0][6])) + 1;
    if (_ts_taddr > 0 && _ts_tlen > 0) {
        array_push(_segs, { start: _ts_taddr, finish: _ts_taddr + max(_ts_tlen, 16), owner: id });
    }
}
	
	// ================================================================
	// PASS 7: ZERO-BYTE PHANTOM CATCHER
	// ================================================================
	// Catch zero-byte nodes (like NAMED_LOC) that point into a danger zone
	//
	// Restricted to the nodes it was written for. A node that HAS a body is
	// already measured against every other segment by the pairwise pass above,
	// which compares whole ranges. Re-testing its start address alone added
	// nothing and mis-fired: a conflict between two unrelated nodes flagged
	// every sized node whose pc_address happened to fall inside that range,
	// turning one real conflict into a row of red boxes with no shared cause.
with (obj_c64_node) {
	    if (!is_conflicted && !is_dragging && total_node_size == 0) {
	        is_conflicted = scr_is_address_conflicted(pc_address);
	    }
	}
	
	global.memory_bar_dirty = true;
	scr_build_memory_bar_cache();
	
	// ================================================================
	// PASS 8: INSTRUCTION OPERAND / CONSTANT CONFLICT CHECK
	// Catches nodes that REFERENCE a danger address in their operands
	// (e.g. LDA SPRITE_DATA where SPRITE_DATA = $2000 lands in an asset).
	// Mirrors the "full file conflict scan" in scr_code_editor_draw.
	// ================================================================
var _am8 = instance_exists(obj_asset_manager) ? obj_asset_manager : noone;

var _is_danger_p8 = method({am8: _am8}, function(_addr) {
	    if (!instance_exists(am8)) return false;
	    for (var _ai = 0; _ai < ds_list_size(am8.asset_list); _ai++) {
	        var _a = am8.asset_list[| _ai];
	        // BITMAP occupies three disjoint regions, not one flat span from the
	        // base — see scr_bmp_regions. Test each independently, or a write
	        // into the screen block goes undetected and a write into the gap
	        // between blocks falsely trips.
	        if (_a.type == "BITMAP") {
	            if (_a.file != "" && buffer_exists(_a.buffer)) {
	                var _p8_br = scr_bmp_regions(_a.address);
	                if (_addr >= _p8_br.bmp_addr && _addr < _p8_br.bmp_addr + _p8_br.bmp_size) return true;
	                if (_addr >= _p8_br.scr_addr && _addr < _p8_br.scr_addr + _p8_br.scr_size) return true;
	                if (_addr >= _p8_br.col_addr && _addr < _p8_br.col_addr + _p8_br.col_size) return true;
	            }
	            continue;
	        }

	        var _asz = 0;
	        if (_a.type == "SPRITE_SET" || _a.type == "SID_MUSIC")
	            _asz = buffer_exists(_a.buffer) ? max(1, buffer_get_size(_a.buffer) - 2) : 0;
	        else
	            continue; // only binary assets that physically occupy C64 RAM
	        if (_asz > 0 && _addr >= _a.address && _addr < _a.address + _asz) return true;
	    }
	    return false;
	});
	
with (obj_c64_node) {
	    if (is_conflicted) continue;
	    if (node_type != "NORMAL" && node_type != "BRANCH" && node_type != "MACRO_CODE") continue;
	    for (var _ii = 0; _ii < array_length(instructions); _ii++) {
	        if (array_length(instructions[_ii]) < 2) continue;
	        var _mop = string_lower(string(instructions[_ii][0]));
            
	        // Do not flag jumps/calls/branches as collisions (calling an asset is fine)
	        var _is_jump = (string_pos("jsr", _mop) > 0 || string_pos("jmp", _mop) > 0 ||
	                        string_pos("bne", _mop) > 0 || string_pos("beq", _mop) > 0 ||
	                        string_pos("bcc", _mop) > 0 || string_pos("bcs", _mop) > 0 ||
	                        string_pos("bpl", _mop) > 0 || string_pos("bmi", _mop) > 0);
	        if (_is_jump) continue;

	        // Only check absolute/indirect/zp modes and consts — not immediates
	        // Only flag instructions that WRITE to memory
	        var _is_writer = (
	            string_pos("sta", _mop) == 1 || string_pos("stx", _mop) == 1 || string_pos("sty", _mop) == 1 ||
	            string_pos("inc", _mop) == 1 || string_pos("dec", _mop) == 1 ||
	            (string_pos("asl", _mop) == 1 && _mop != "asl_a") ||
	            (string_pos("lsr", _mop) == 1 && _mop != "lsr_a") ||
	            (string_pos("rol", _mop) == 1 && _mop != "rol_a") ||
	            (string_pos("ror", _mop) == 1 && _mop != "ror_a") ||
	            _mop == "const"
	        );
	        if (!_is_writer) continue;
	        if (string_pos("_abs", _mop) == 0 && string_pos("_ind", _mop) == 0
	        &&  string_pos("_zp",  _mop) == 0 && _mop != "const") continue;
	        // Prefer resolved label address (index 2), fall back to direct operand (index 1)
	        var _opval = -1;
	        if (array_length(instructions[_ii]) > 2 && is_real(instructions[_ii][2]))
	            _opval = real(instructions[_ii][2]);
	        else if (is_real(instructions[_ii][1]))
	            _opval = real(instructions[_ii][1]);
			if (_opval >= 0 && _is_danger_p8(_opval)) {
	            show_debug_message("CONFLICT PASS 8: " + string(node_type) + "#" + string(id)
	                + " writes $" + string_upper(decimal_to_hex(_opval)) + " (" + _mop + ")");
	            // Sprite pointer table exception: last 8 bytes of any 1K screen block
	            var _spr_ptr_offset = _opval & 0x03FF;
	            var _is_spr_ptr8    = (_spr_ptr_offset >= 0x03F8 && _spr_ptr_offset <= 0x03FF);
	            // Friendly Fire Check: Is this address actually inside MY OWN memory range?
	            var _is_self = (_opval >= pc_address && _opval < pc_address + total_node_size);
	            if (!_is_self && !_is_spr_ptr8) {
	                is_conflicted = true;
	                break;
	            }
	        }
	    }
}

	// ================================================================
    // PASS 9: POPULATE CROSS-BLOCK LABEL REGISTRY
    // ================================================================
    global.code_block_labels = {};
    with (obj_c64_node) {
        if (node_type == "MACRO_CODE" && is_connected && array_length(instructions) > 0) {
            var _cb_text = string(instructions[0][1]);
            if (_cb_text != "") {
                var _cb_lines = string_split(_cb_text, "\n");
                var _cb_pc    = pc_address;
                for (var _cli = 0; _cli < array_length(_cb_lines); _cli++) {
                    var _cl = string_trim(_cb_lines[_cli]);
                    var _colon_pos = string_pos(":", _cl);
                    if (_colon_pos > 1) {
                        var _lbl = string_trim(string_copy(_cl, 1, _colon_pos - 1));
                        if (string_char_at(_lbl, 1) == ".") _lbl = string_delete(_lbl, 1, 1);
                        if (_lbl != "" && string_pos(" ", _lbl) == 0) {
                            global.code_block_labels[$ _lbl] = _cb_pc;
                        }
                    }
                }
            }
        }
    }

	// ================================================================
	// PASS 10: MACRO_CODE CONFLICT CHECK
	// ================================================================
	with (obj_c64_node) {
	    if (node_type != "MACRO_CODE") continue;
	    if (!is_connected) continue;
	    var _code_text = string(instructions[0][1]);
	    if (_code_text == "") continue;
	    if (!code_cache_dirty && array_length(p9_parsed_cache) > 0) {
	        var _full_parsed = p9_parsed_cache;
	    } else {
	        var _full_parsed = scr_parse_asm_text(_code_text);
	        p9_parsed_cache = _full_parsed;
	    }
	    var _am9 = instance_exists(obj_asset_manager) ? obj_asset_manager : noone;
	    for (var _fi = 0; _fi < array_length(_full_parsed); _fi++) {
	        var _inst = _full_parsed[_fi];
	        var _op = string_lower(_inst[0]);
	            
	        // Do not flag jumps/calls/branches as collisions
	        var _is_jump = (string_pos("jsr", _op) > 0 || string_pos("jmp", _op) > 0 ||
	                        string_pos("bne", _op) > 0 || string_pos("beq", _op) > 0 ||
	                        string_pos("bcc", _op) > 0 || string_pos("bcs", _op) > 0 ||
	                        string_pos("bpl", _op) > 0 || string_pos("bmi", _op) > 0);
	        if (_is_jump) continue;

	        var _is_writer9 = (
	            string_pos("sta", _op) == 1 || string_pos("stx", _op) == 1 || string_pos("sty", _op) == 1 ||
	            string_pos("inc", _op) == 1 || string_pos("dec", _op) == 1 ||
	            (string_pos("asl", _op) == 1 && _op != "asl_a") ||
	            (string_pos("lsr", _op) == 1 && _op != "lsr_a") ||
	            (string_pos("rol", _op) == 1 && _op != "rol_a") ||
	            (string_pos("ror", _op) == 1 && _op != "ror_a") ||
	            _op == "const"
	        );

	        // DEBUG: log all instructions being checked


	        if (!_is_writer9) continue;
	        if (string_pos("_abs", _op) == 0 && string_pos("_ind", _op) == 0 &&
	            string_pos("_zp",  _op) == 0 && _op != "const") continue;

	        if (array_length(_inst) > 1 && is_real(_inst[1])) {
	            var _addr9 = real(_inst[1]);
	            if (_am9 != noone) {
	                for (var _ai = 0; _ai < ds_list_size(_am9.asset_list); _ai++) {
	                    var _a9 = _am9.asset_list[| _ai];
	                    var _asz9 = 0;

	                    // ONLY check binary assets that physically occupy C64 RAM
	                    // BYTE_DATA and TEXT_DATA are writable variable storage — skip
	                    var _is_me = (_addr9 >= pc_address && _addr9 < pc_address + total_node_size);

	                    // Sprite pointer tables: $x3F8-$x3FF for any screen position within a VIC bank.
	                    // Screen can be at $x000, $x400, $x800, $xC00 etc within the bank.
	                    // Sprite ptrs are always screen_base + $3F8, so check the last 8 bytes of any 1K block.
	                    var _screen_block_offset = _addr9 & 0x03FF; // offset within 1K screen block
	                    var _is_spr_ptr    = (_screen_block_offset >= 0x03F8 && _screen_block_offset <= 0x03FF);
	                    var _is_screen_ram = (_screen_block_offset >= 0x0000 && _screen_block_offset <= 0x03E7);

	                    // BITMAP occupies THREE disjoint regions, not one flat 10192-byte
	                    // span from the base — see scr_bmp_regions. In VIC bank 2 they
	                    // aren't even adjacent (bitmap $8000, colour $9F40, screen $BC00),
	                    // so a flat span both over-claimed the gap between them and missed
	                    // the screen block entirely. Test each region on its own bounds.
	                    //
	                    // NOTE: _is_screen_ram remains a blanket exemption (any address
	                    // whose low 10 bits land in $000-$3E7). It exists so legitimate
	                    // screen-RAM writes don't flag, but it exempts the great majority
	                    // of addresses from bitmap conflict detection. Preserved as-is
	                    // here to avoid a behaviour change; tightening it to exempt only
	                    // the DISPLAYED bitmap's screen block is separate work.
	                    if (_a9.type == "BITMAP") {
	                        if (_a9.file == "" || !buffer_exists(_a9.buffer)) continue;
	                        if (_is_me || _is_spr_ptr || _is_screen_ram) continue;

	                        var _p9_br  = scr_bmp_regions(_a9.address);
	                        var _p9_hit = false;
	                        if (_addr9 >= _p9_br.bmp_addr && _addr9 < _p9_br.bmp_addr + _p9_br.bmp_size) _p9_hit = true;
	                        if (_addr9 >= _p9_br.scr_addr && _addr9 < _p9_br.scr_addr + _p9_br.scr_size) _p9_hit = true;
	                        if (_addr9 >= _p9_br.col_addr && _addr9 < _p9_br.col_addr + _p9_br.col_size) _p9_hit = true;

	                        if (_p9_hit) {
	                            is_conflicted = true;
	                            break;
	                        }
	                        continue;
	                    }

	                    if (_a9.type == "SPRITE_SET" || _a9.type == "SID_MUSIC")
	                        _asz9 = buffer_exists(_a9.buffer) ? max(1, buffer_get_size(_a9.buffer) - 2) : 0;
	                    else {
	                        continue;
	                    }

	                    if (_asz9 <= 0) continue;

			 		    if (!_is_me && !_is_spr_ptr && !_is_screen_ram && _addr9 >= _a9.address && _addr9 < _a9.address + _asz9) {
	                        show_debug_message("CONFLICT PASS 10: MACRO_CODE#" + string(id)
	                            + " writes $" + string_upper(decimal_to_hex(_addr9))
	                            + " (" + _op + ") inside asset " + string(_a9.name));
	                        is_conflicted = true;
	                        break;
	                    }
	                }
	            }
	            if (is_conflicted) break;
	        }
	    }
	}

	// ================================================================
	// PASS 11: MACRO_TEXT_SCROLL JSR-MODE CALL DETECTION
	// ================================================================
	with (obj_c64_node) {
	    if (node_type != "MACRO_TEXT_SCROLL") continue;
	    var _jmode = (array_length(instructions[0]) > 11 && is_real(instructions[0][11]))
	               ? real(instructions[0][11]) : 0;
	    if (_jmode != 1) {
	        jsr_called = 1;
	        continue;
	    }
	    var _raw_alias = (array_length(instructions[0]) > 12 && is_string(instructions[0][12]))
	                   ? string(instructions[0][12]) : "";
	    var _alias  = (_raw_alias != "") ? _raw_alias : ("ts" + string(real(id)));
	    var _label  = string_lower(_alias + "_scrl");
	    var _ts_id  = id;
	    var _found  = 0;

	    with (obj_c64_node) {
	        if (id == _ts_id) continue;
	        for (var _ji = 0; _ji < array_length(instructions); _ji++) {
	            if (array_length(instructions[_ji]) < 2) continue;
	            if (string_lower(string(instructions[_ji][0])) != "jsr") continue;
	            if (!is_string(instructions[_ji][1])) continue;
	            if (string_lower(string(instructions[_ji][1])) == _label) {
	                _found = 1;
	                break;
	            }
	        }
	        if (_found) break;
	    }
	    jsr_called = _found;
	}

	// ================================================================
	// PASS 12: MACRO_BMP CHAR-ROM SHADOW WARNING (advisory only)
	// The VIC sees char ROM at $1000-$1FFF (bank 0) and $9000-$9FFF
	// (bank 2) regardless of RAM contents. A DISPLAYED bitmap whose
	// 8000-byte span crosses either shadow renders garbage in the
	// overlapping rows. RAM is still there for the CPU, so a bitmap
	// parked in the shadow is perfectly valid as DATA (a tile sheet
	// read by MACRO_MOVE_BMP_BLOCK) — hence advisory, not a block.
	//   bank 0: only $0000 is legal (spans $0000-$1F3F, clear of $1000?
	//           no — it hits it. bank 0 has no clean bitmap slot below
	//           $2000, so $2000 is the only legal base).
	//   bank 2: only $A000 is legal ($8000 spans $8000-$9F3F, ~40% under
	//           the shadow). Screen then sits at $B800/$BC00.
	// ================================================================
	with (obj_c64_node) {
	    if (node_type != "MACRO_BMP") continue;

	    bmp_shadow_warn = false;

	    var _sw_addr = 0x4000;
	    if (is_real(instructions[0][2])) {
	        _sw_addr = real(instructions[0][2]);
	    }

	    var _sw_end   = _sw_addr + 8000;
	    var _sw_bank  = floor(_sw_addr / 0x4000);
	    var _sw_hit   = false;

	    if (_sw_bank == 0) {
	        if (_sw_addr < 0x2000 && _sw_end > 0x1000) _sw_hit = true;
	    }
	    if (_sw_bank == 2) {
	        if (_sw_addr < 0xA000 && _sw_end > 0x9000) _sw_hit = true;
	    }

	    bmp_shadow_warn = _sw_hit;
	}

// ---- SHOW CODE PANEL ----
// Second half of the listing build, deliberately down here rather than beside
// scr_show_code_build(): attributing rows to LABEL and plain opcode nodes needs
// pc_address, and those are not assigned until the passes above have run.
scr_show_code_attribute();
}