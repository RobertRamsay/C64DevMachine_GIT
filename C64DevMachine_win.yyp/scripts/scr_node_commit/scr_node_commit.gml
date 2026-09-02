	/// @desc scr_node_commit(target, idx, input_string)
	/// @param {Id.Instance} target            - the node being edited
	/// @param {real}        idx               - field index (-1 = address badge)
	/// @param {string}      input_string      - the committed string value
	/// Commits a typed value to the correct field on the target node.

	function scr_node_commit(_target, _idx, _input) {

	if (_idx == -99) {
		    var _raw = string_replace_all(string_trim(_input), " ", "_");
		    if (_raw != "") {
		        var _has_prefix = (string_upper(string_copy(_raw, 1, 3)) == "UV_");
		        var _prefixed = _has_prefix ? ("UV_" + string_copy(_raw, 4, string_length(_raw) - 3)) : ("UV_" + _raw);
		        with (obj_workspace_manager) {
		            if (uv_pending_enc == "str") {
		                // Spawn a NEW_STR node into the VARIABLES ORG
		                var _org = noone;
		                with (obj_c64_node) {
		                    if (node_type == "ORG" && node_title == "VARIABLES") { _org = id; break; }
		                }
		                if (instance_exists(_org)) {
		                    var _bottom_y = _org.y + _org.height;
		                    with (obj_c64_node) {
		                        if (org_parent == _org && is_connected && y + height > _bottom_y)
		                            _bottom_y = y + height;
		                    }
		                    var _nl          = instance_create_layer(_org.x, _bottom_y, "Layer_Nodes", obj_c64_node);
		                    _nl.node_title   = "UV STR";
		                    _nl.node_type    = "NEW_STR";
		                    _nl.instructions = [["new_str", _prefixed, 0xC000, "HELLO WORLD ", 0, ""]];
		                    _nl.pc_address   = 0xC000;
		                    _nl.is_connected = true;
		                    _nl.org_parent   = _org;
		                    with (_nl) { event_user(0); }
		                    global.addresses_dirty = true;
		                }
		            } else {
		                scr_uv_add(_prefixed, uv_pending_size, uv_pending_enc);
		            }
		        }
		    }
		    return;
		}

	// -------------------------------------------------------
	// HEADER RENAME (idx == -77) — write to custom_title
	// Empty string reverts to the default node_title.
	// -------------------------------------------------------
	if (_idx == -77) {
	    if (!instance_exists(_target)) return;
	    _target.custom_title       = string_trim(_input);
	    _target.stats_cache_dirty  = true;
	    _target.height_dirty       = true;
	    global.undo_dirty          = true;
	    return;
	}


	// -------------------------------------------------------
	// VAR RENAME (idx == -78) — NAMED_LOC / NEW_STR real name.
	// Blocks on duplicate name; on success rewrites every known
	// reference (scr_find_var_references), the source node, and
	// (NAMED_LOC only) the global.named_loc_map / meta records.
	// -------------------------------------------------------
	if (_idx == -78) {
	    if (!instance_exists(_target)) return;
	    var _old_name = string(_target.instructions[0][1]);
	    var _raw = string_replace_all(string_trim(_input), " ", "_");
	    if (_raw == "") return;
	    var _has_prefix = (string_upper(string_copy(_raw, 1, 3)) == "UV_");
	    var _new_name = _has_prefix
	        ? ("UV_" + string_copy(_raw, 4, string_length(_raw) - 3))
	        : ("UV_" + _raw);
	    if (_new_name == _old_name) return;

	    // Duplicate check — NAMED_LOC names live in named_loc_map (authoritative);
	    // NEW_STR names aren't map-tracked, so scan nodes for those.
	    var _dupe = false;
	    if (_target.node_type == "NAMED_LOC") {
	        if (ds_map_exists(global.named_loc_map, _new_name)) _dupe = true;
	    }
	    if (!_dupe) {
	        with (obj_c64_node) {
	            if (id == _target) continue;
	            if (node_type != "NAMED_LOC" && node_type != "NEW_STR") continue;
	            if (array_length(instructions) > 0 && array_length(instructions[0]) > 1
	                && string(instructions[0][1]) == _new_name) {
	                _dupe = true;
	                break;
	            }
	        }
	    }
	    if (_dupe) {
	        scr_show_message("VAR NAME EXISTS:\n\n" + _new_name + "\n\nChoose a different name.");
	        return;
	    }

	    // Rewrite every node that references the old name
	    var _refs = scr_find_var_references(_old_name, _target);
	    var _new_name_upper = string_upper(_new_name);
	    for (var _ri = 0; _ri < array_length(_refs); _ri++) {
	        var _rn = _refs[_ri].node;
	        if (!instance_exists(_rn)) continue;
	        var _rn_slots = _refs[_ri].slots;
	        with (_rn) {
	            for (var _si = 0; _si < array_length(_rn_slots); _si++) {
	                instructions[0][_rn_slots[_si]] = _new_name_upper;
	            }
	        }
	    }

	    // NAMED_LOC — re-key named_loc_map and update named_loc_meta in place
	    if (_target.node_type == "NAMED_LOC") {
	        if (ds_map_exists(global.named_loc_map, _old_name)) {
	            var _addr = ds_map_find_value(global.named_loc_map, _old_name);
	            ds_map_delete(global.named_loc_map, _old_name);
	            ds_map_add(global.named_loc_map, _new_name, _addr);
	        }
	        for (var _mi = 0; _mi < array_length(global.named_loc_meta); _mi++) {
	            if (global.named_loc_meta[_mi].name == _old_name) {
	                global.named_loc_meta[_mi].name = _new_name;
	                break;
	            }
	        }
	        global.named_loc_meta_dirty = true;
	    }

	    _target.instructions[0][1] = _new_name;
	    if (_target.node_type == "NEW_STR") {
	        _target.node_title = "UV STR";
	    }
	    _target.stats_cache_dirty  = true;
	    _target.height_dirty       = true;
	    global.undo_dirty          = true;
	    global.addresses_dirty     = true;
	    scr_c64_do_update_addresses();
	    with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
	    return;
	}

	if (!instance_exists(_target)) exit;

	    // -------------------------------------------------------
	    // MACRO_CODE (idx -2 = descriptor, idx 0 = code text)
	    // -------------------------------------------------------
	    if (_target.node_type == "MACRO_CODE") {
	        if (_idx == -2) {
	            _target.code_descriptor = _input;
	            _target.height_dirty = true;
	        } else if (_idx == 0) {
	            _target.instructions[0][1] = _input;
	            _target.height_dirty = true;
	        }
	        return;
	    }

	    // -------------------------------------------------------
	    // ADDRESS BADGE (idx == -1)
	    // -------------------------------------------------------

	    if (_idx == -1) {
	        var _addr_val = 0;
	        if (string_char_at(_input, 1) == "$") {
	            var _clean = string_delete(_input, 1, 1);
	            _addr_val = real(hex_to_decimal(string_upper(_clean)));
	        } else if (global.use_hex_display) {
	            _addr_val = real(hex_to_decimal(string_upper(_input)));
	        } else {
	            var _digits = string_digits(_input);
	            _addr_val = (_digits != "") ? real(_digits) : 0;
	        }
	        _target.pc_address = _addr_val;

	        // Overlap check for MACRO_PRINT data address
	        if (_target.node_type == "MACRO_PRINT") {
	            var _new_start = _target.pc_address;
	            var _new_end   = _new_start + string_length(
	                                 (array_length(_target.instructions[0]) > 5)
	                                 ? string(_target.instructions[0][5]) : "");
	            var _clash = false;
	            with (obj_c64_node) {
	                if (id == _target) continue;
	                if (node_type == "LABEL" || node_type == "COMMENT" || node_type == "EXECUTE") continue;
	                var _other_end = pc_address + total_node_size;
	                if (_new_start < _other_end && _new_end > pc_address) {
	                    _clash = true;
	                    break;
	                }
	            }
	            _target.ascii_address_valid = !_clash;
	        }
	        return;
	    }

	    // -------------------------------------------------------
	    // FIELD VALUES (idx >= 0)
	    // -------------------------------------------------------

	    var _is_comment = (_target.node_type == "COMMENT");

	    // --- COMMENT / DATA_TEXT / RAW_DATA (plain string store) ---
	    if (_is_comment || _target.node_type == "DATA_TEXT" || _target.node_type == "RAW_DATA") {
	        _target.instructions[_idx][1] = _input;

	    // --- LABEL ---
		} else if (_target.node_type == "LABEL") {
	        var _old_label = string(_target.instructions[_idx][1]);
	        // Sanitise FIRST: spaces -> underscores (so uniqueness sees the stored form)
	        var _new_label = string_replace_all(string_trim(_input), " ", "_");
	        // Uniqueness: always check against other LABELs (_target excluded by helper).
	        // Runs post-sanitise so "My label" and "My_label" can't both resolve to a dupe.
	        if (_new_label != "") {
	            _new_label = scr_make_unique_node_name(_new_label, _target);
	        }
	        _target.instructions[_idx][1] = _new_label;
	        if (array_length(_target.instructions[_idx]) > 2) {
	            _target.instructions[_idx][2] = _new_label;
	        }
	        // Propagate rename to all JMP/JSR/branch operands referencing the old label
	        if (_old_label != _new_label && _old_label != "") {
	            with (obj_c64_node) {
	                if (!variable_instance_exists(id, "instructions")) continue;
	                for (var _ri = 0; _ri < array_length(instructions); _ri++) {
	                    if (array_length(instructions[_ri]) < 2) continue;
	                    if (!is_string(instructions[_ri][1])) continue;
	                    if (string_upper(instructions[_ri][1]) != string_upper(_old_label)) continue;
	                    var _mn = string_lower(string(instructions[_ri][0]));
	                    var _is_j = (string_pos("jmp", _mn) > 0 || string_pos("jsr", _mn) > 0);
	                    var _is_b = (string_char_at(_mn, 1) == "b" && string_length(_mn) == 3);
	                    if (_is_j || _is_b) {
	                        instructions[_ri][1] = _new_label;
	                        if (array_length(instructions[_ri]) > 2) instructions[_ri][2] = _new_label;
	                    }
	                }
	                // COND_IF stores its GOTO target in instructions[0][3] (opcode slot
	                // is "cond_if", so the jump/branch test above never catches it)
	                if ((node_type == "COND_IF" || node_type == "COND_IF_WORD") &&
	                    array_length(instructions[0]) > 3 &&
	                    is_string(instructions[0][3]) &&
	                    string_upper(instructions[0][3]) == string_upper(_old_label)) {
	                    instructions[0][3] = _new_label;
	                }
	                // MACRO_COLL_ADV holds 16 tile-type label targets:
	                // slots 5..12 (T1..T8) and 18..25 (T9..T16)
	                if (node_type == "MACRO_COLL_ADV") {
	                    var _ca_slots = [5,6,7,8,9,10,11,12,18,19,20,21,22,23,24,25];
	                    for (var _csi = 0; _csi < array_length(_ca_slots); _csi++) {
	                        var _cs = _ca_slots[_csi];
	                        if (array_length(instructions[0]) > _cs &&
	                            is_string(instructions[0][_cs]) &&
	                            string_upper(instructions[0][_cs]) == string_upper(_old_label)) {
	                            instructions[0][_cs] = _new_label;
	                        }
	                    }
	                }
	            }
	        }

	   // --- MACRO_MAP ---
	    } else if (_target.node_type == "MACRO_MAP") {
	        if (_idx == 6) {
	            // ZP source pointer — hex input, clamp $00-$FC (needs 4 bytes)
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _zp_val = real(hex_to_decimal(string_upper(_clean)));
	            _zp_val = clamp(_zp_val, 0x00, 0xFC);
	            while (array_length(_target.instructions[0]) <= 6) { array_push(_target.instructions[0], 0x50); }
	            _target.instructions[0][6] = _zp_val;
	        }

		// --- KEYBOARD MATRIX NODES ---
	    } else if (_target.node_type == "MACRO_LETTERS"
	            || _target.node_type == "MACRO_FNNUMBERS"
	            || _target.node_type == "MACRO_MISCKEYS") {
	        if (_idx == 100) {
	            // ZP BASE. Clamped so the whole held-bits block stays inside
	            // zero page, whichever category this is.
	            var _kb_clean = (string_char_at(_input, 1) == "$")
	                          ? string_delete(_input, 1, 1) : _input;
	            var _kb_zp    = real(hex_to_decimal(string_upper(_kb_clean)));
	            var _kb_cat   = scr_key_category_list(_target.node_type);
	            var _kb_need  = ceil(array_length(_kb_cat.keys) / 8);
	            _target.instructions[0][1] = clamp(_kb_zp, 0x02, 0xFF - _kb_need);
	        }

		// --- MACRO_MOUSE ---
	    } else if (_target.node_type == "MACRO_MOUSE") {
	        if (_idx == 100) {
	            // ZP BASE. Clamped so base+6 cannot run off the end of zero
	            // page — the block is seven bytes and the last one is scratch.
	            var _mse_clean = (string_char_at(_input, 1) == "$")
	                           ? string_delete(_input, 1, 1) : _input;
	            var _mse_zp = real(hex_to_decimal(string_upper(_mse_clean)));
	            _target.instructions[0][2] = clamp(_mse_zp, 0x02, 0xF9);
	        } else if (_idx >= 200) {
	            _target.instructions[_idx - 200][1] = _input;
	        }

		// --- MACRO_JOY ---
	    } else if (_target.node_type == "MACRO_JOY") {
	        if (_idx == 100) {
	            // ZP address field
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][2] = real(hex_to_decimal(string_upper(_clean)));
	        } else if (_idx >= 200) {
	            // Branch label slot
	            _target.instructions[_idx - 200][1] = _input;
	        }
		
		// =============================================================
		// MACRO_SCROLL — INPUT COMMIT
		// Paste inside the "Enter key = commit value to node" block
		// in obj_workspace_manager Step_0, inside the is_entering_text
		// section, alongside the existing MACRO_SID / MACRO_SPR cases.
		//
		// Handles indices 1 (start_row) and 2 (row_count).
		// Clamps values to valid ranges on commit.
		// =============================================================

	} else if (_target.node_type == "MACRO_SCROLL") {
		    var _digits = string_digits(_input);
		    var _val    = (_digits != "") ? real(_digits) : 0;

			if (_idx == 1) {
		        // START ROW: clamp 0-24, also re-clamp row_count to fit
		        var _new_start = clamp(_val, 0, 24);
		        _target.instructions[0][1] = _new_start;
		        var _cur_count = (array_length(_target.instructions[0]) > 2 && is_real(_target.instructions[0][2])) ? real(_target.instructions[0][2]) : 16;
		        _target.instructions[0][2] = clamp(_cur_count, 1, 25 - _new_start);
		    } else if (_idx == 2) {
		        // ROW COUNT: clamp 1 to (25 - start_row)
		        var _cur_start = (array_length(_target.instructions[0]) > 1 && is_real(_target.instructions[0][1])) ? real(_target.instructions[0][1]) : 0;
		        var _clamped = clamp(_val, 1, 25 - _cur_start);
		        _target.instructions[0][2] = _clamped;
		        var _col_mode = (array_length(_target.instructions[0]) > 3 && is_real(_target.instructions[0][3]))
		                      ? real(_target.instructions[0][3]) : 1;
		        if (_col_mode == 2 && _clamped > 8) {
		            show_debug_message("MACRO_SCROLL WARN: INLINE colour with " + string(_clamped)
		                               + " rows may overrun vblank. Consider DEFERRED.");
		        }
		    } else if (_idx == 8) {
		        // MAP IDX: decimal, clamp to the chosen tileset's map_count
		        var _mm_max_idx = 0;
		        var _mm_tileset_name = (array_length(_target.instructions[0]) > 7 && is_string(_target.instructions[0][7])) ? string(_target.instructions[0][7]) : "";
		        if (_mm_tileset_name != "" && instance_exists(obj_asset_manager)) {
		            var _mm_am = obj_asset_manager;
		            for (var _mm_ai = 0; _mm_ai < ds_list_size(_mm_am.asset_list); _mm_ai++) {
		                var _mm_a = ds_list_find_value(_mm_am.asset_list, _mm_ai);
		                if (_mm_a.type == "META_TILESET" && _mm_a.name == _mm_tileset_name) {
		                    if (variable_struct_exists(_mm_a.meta, "map_count")) {
		                        _mm_max_idx = max(0, _mm_a.meta.map_count - 1);
		                    }
		                    break;
		                }
		            }
		        }
		        _target.instructions[0][8] = clamp(_val, 0, _mm_max_idx);
		    } else if (_idx == 9) {
		        // BASE ADDR: hex input ($xxxx or plain hex digits), floor $0400
		        var _mm_clean    = (string_char_at(_input, 1) == "$") ? string_delete(_input, 1, 1) : _input;
		        var _mm_addr_val = real(hex_to_decimal(string_upper(_mm_clean)));
		        _target.instructions[0][9] = clamp(_mm_addr_val, 0x0400, 0xFFFF);
		    }
		
		// --- MACRO_TEXT_SCROLL ---
	    } else if (_target.node_type == "MACRO_TEXT_SCROLL") {
	        if (_idx == 1) {
	            // Scroll row: clamp 0-24
	            var _digits = string_digits(_input);
	            _target.instructions[0][1] = clamp((_digits != "") ? real(_digits) : 23, 0, 24);
	} else if (_idx == 5) {
	            // Data address: follows global hex mode; $xxxx always accepted
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][5] = real(hex_to_decimal(string_upper(_clean)));
	            } else if (global.use_hex_display) {
	                _target.instructions[0][5] = real(hex_to_decimal(string_upper(_input)));
	            } else {
	                var _d = string_digits(_input);
	                _target.instructions[0][5] = (_d != "") ? real(_d) : 0xC000;
	            }
			} else if (_idx == 6) {
	            // Text string: store as-is (preserve case for command parsing)
	            _target.instructions[0][6] = _input;
			} else if (_idx == 7) {
	            // PRE-NOP delay: clamp 0-255
	            var _digits = string_digits(_input);
	            _target.instructions[0][7] = clamp((_digits != "") ? real(_digits) : 6, 0, 255);
	        } else if (_idx == 8) {
	            // POST-NOP delay: clamp 0-255
	            var _digits = string_digits(_input);
	            _target.instructions[0][8] = clamp((_digits != "") ? real(_digits) : 27, 0, 255);
	        } else if (_idx == 12) {
	            // Alias — strip spaces, store as plain string
	            while (array_length(_target.instructions[0]) <= 12) array_push(_target.instructions[0], "");
	            _target.instructions[0][12] = string_replace_all(string_lower(_input), " ", "_");
	        }
		
		// --- MACRO_MOVE ---
		} else if (_target.node_type == "MACRO_MOVE") {
		    if (_idx == 2 || _idx == 3) {
		        // DX / DY literal delta — signed, -15..15
		        var _is_neg = (string_char_at(_input, 1) == "-");
		        var _digits = string_digits(_input);
		        var _val    = (_digits != "") ? real(_digits) : 0;
		        if (_is_neg) _val = -_val;
		        _target.instructions[0][_idx] = clamp(_val, -64, 64);
		    } else if (_idx == 11) {
		        // MIN X — unsigned, full 9-bit reach for wide-X mode
		        var _digits = string_digits(_input);
		        _target.instructions[0][11] = clamp((_digits != "") ? real(_digits) : 0, 0, 343);
		    } else if (_idx == 12) {
		        // MAX X — unsigned; capped at 255 unless 9TH BIT (wide-X) is on
		        var _mm_widex = real(_target.instructions[0][4]);
		        var _mm_x_cap = (_mm_widex == 1) ? 343 : 255;
		        var _digits = string_digits(_input);
		        _target.instructions[0][12] = clamp((_digits != "") ? real(_digits) : 0, 0, _mm_x_cap);
		    } else if (_idx == 13 || _idx == 14) {
		        // MIN Y / MAX Y — unsigned, 0-255
		        var _digits = string_digits(_input);
		        _target.instructions[0][_idx] = clamp((_digits != "") ? real(_digits) : 0, 0, 255);
		    }

		// --- MACRO_SEEK ---
		} else if (_target.node_type == "MACRO_SEEK") {
		    while (array_length(_target.instructions[0]) < 18) array_push(_target.instructions[0], 0);
		    if (_idx == 2) {
		        // TGT X literal — allow 0..511 for 9th-bit reach
		        var _is_neg = (string_char_at(_input, 1) == "-");
		        var _digits = string_digits(_input);
		        var _val    = (_digits != "") ? real(_digits) : 0;
		        if (_is_neg) _val = 0;
		        _target.instructions[0][2] = clamp(_val, 0, 511);
		    } else if (_idx == 3) {
		        // TGT Y literal — 0..255
		        var _digits = string_digits(_input);
		        _target.instructions[0][3] = clamp((_digits != "") ? real(_digits) : 0, 0, 255);
		    } else if (_idx == 4) {
		        // SPEED — 1..255
		        var _digits = string_digits(_input);
		        _target.instructions[0][4] = clamp((_digits != "") ? real(_digits) : 1, 1, 255);
		    } else if (_idx == 5) {
		        // NEAR DIST — 0..255 (0 = off)
		        var _digits = string_digits(_input);
		        _target.instructions[0][5] = clamp((_digits != "") ? real(_digits) : 0, 0, 255);
		    } else if (_idx == 6) {
		        // SPD-NEAR — 1..255
		        var _digits = string_digits(_input);
		        _target.instructions[0][6] = clamp((_digits != "") ? real(_digits) : 1, 1, 255);
		    } else if (_idx == 11 || _idx == 13 || _idx == 15 || _idx == 17) {
		        // VAR-name slots from picker; "[clear]" empties
		        if (_input == "[clear]" || _input == "") {
		            _target.instructions[0][_idx] = "";
		        } else {
		            _target.instructions[0][_idx] = string_upper(_input);
		        }
		    }
		    global.addresses_dirty = true;

		// --- MACRO_MOVE_BMP_BLOCK ---
		} else if (_target.node_type == "MACRO_MOVE_BMP_BLOCK") {
		    if (_idx == 1 || _idx == 2) {
		        // Bitmap base addresses — hex
		        var _clean = (string_char_at(_input, 1) == "$")
		                   ? string_delete(_input, 1, 1) : _input;
		        _target.instructions[0][_idx] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 0xFFFF);
		    } else if (_idx >= 3 && _idx <= 8) {
		        // SX/SY/DX/DY/W/H — numeric, cell coords
		        var _d = string_digits(_input);
		        var _val = (_d != "") ? real(_d) : 0;
		        var _max = 40;
		        if (_idx == 4 || _idx == 6) _max = 25; // Y
		        if (_idx == 7) _max = 40;              // W
		        if (_idx == 8) _max = 25;              // H
		        _target.instructions[0][_idx] = clamp(_val, (_idx >= 7 ? 1 : 0), _max);
		    } else if (_idx >= 9 && _idx <= 12) {
		        // VAR name slots — from VAR picker; "[clear]" empties
		        while (array_length(_target.instructions[0]) <= _idx) array_push(_target.instructions[0], "");
		        if (_input == "[clear]" || _input == "") {
		            _target.instructions[0][_idx] = "";
		        } else {
		            _target.instructions[0][_idx] = string_upper(_input);
		        }
		    }
		    global.addresses_dirty = true;

		// --- MACRO_MOVE_MEM ---
		} else if (_target.node_type == "MACRO_MOVE_MEM") {
		    show_debug_message("MOVE_MEM COMMIT: idx=" + string(_idx) + " input=[" + string(_input) + "]");
		    var _clean = (string_char_at(_input, 1) == "$")
		               ? string_delete(_input, 1, 1) : _input;
		    var _val   = real(hex_to_decimal(string_upper(_clean)));
		    _target.instructions[0][_idx] = clamp(_val, 0, 0xFFFF);
		    show_debug_message("MOVE_MEM AFTER: [0]=" + string(_target.instructions[0][0])
		                       + " [1]=$" + string_upper(decimal_to_hex(_target.instructions[0][1]))
		                       + " [2]=$" + string_upper(decimal_to_hex(_target.instructions[0][2]))
		                       + " [3]=$" + string_upper(decimal_to_hex(_target.instructions[0][3])));

		// --- MACRO_FLIP_X ---
		} else if (_target.node_type == "MACRO_FLIP_X") {
	    if (_idx == 1) {
	        var _clean = (string_char_at(_input, 1) == "$")
	                   ? string_delete(_input, 1, 1) : _input;
	        _target.instructions[0][1] = real(hex_to_decimal(string_upper(_clean)));
	    } else if (_idx == 2) {
	        var _digits = string_digits(_input);
	        _target.instructions[0][2] = max(1, (_digits != "") ? real(_digits) : 1);
	    }





	   
	    // --- MACRO_CLEAR_BMP_RECT ---
	    // Slot 1 is the target bitmap base (hex, like every other bmp addr).
	    // Slots 2-5 are char-cell coords: clamped to the 40x25 grid here so a
	    // typo can't produce a rect the compile has to silently trim.
	    } else if (_target.node_type == "MACRO_CLEAR_BMP_RECT") {
	        while (array_length(_target.instructions[0]) < 6) { array_push(_target.instructions[0], 0); }
	        if (_idx == 1) {
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][1] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 0xFFFF);
	        } else if (_idx == 2) {
	            // COL — 0..39
	            var _digits = string_digits(_input);
	            _target.instructions[0][2] = clamp((_digits != "") ? real(_digits) : 0, 0, 39);
	        } else if (_idx == 3) {
	            // ROW — 0..24
	            var _digits = string_digits(_input);
	            _target.instructions[0][3] = clamp((_digits != "") ? real(_digits) : 0, 0, 24);
	        } else if (_idx == 4) {
	            // W — at least 1 cell, and never wider than the grid allows from COL
	            var _cur_col = is_real(_target.instructions[0][2]) ? real(_target.instructions[0][2]) : 0;
	            var _digits  = string_digits(_input);
	            _target.instructions[0][4] = clamp((_digits != "") ? real(_digits) : 1, 1, 40 - _cur_col);
	        } else if (_idx == 5) {
	            // H — at least 1 cell, and never taller than the grid allows from ROW
	            var _cur_row = is_real(_target.instructions[0][3]) ? real(_target.instructions[0][3]) : 0;
	            var _digits  = string_digits(_input);
	            _target.instructions[0][5] = clamp((_digits != "") ? real(_digits) : 1, 1, 25 - _cur_row);
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_PRINT ---
	    } else if (_target.node_type == "MACRO_PRINT") {
	        if (_idx == 5) {
	            // Inline text — uppercase for PETSCII
	            _target.instructions[0][5] = string_upper(_input);
	        } else if (_idx == 6) {
	            // Text data address — hex input
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][6] = real(hex_to_decimal(string_upper(_clean)));
	        } else if (_idx == 13) {
	            // SCR BASE — VIC screen-matrix base, hex input, clamp $0000-$FFFF
	            while (array_length(_target.instructions[0]) <= 13) array_push(_target.instructions[0], 0x0400);
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][13] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 0xFFFF);
	        } else if (_idx == 11 || _idx == 12) {
	            // START / END offsets into TEXT_DATA asset — 16-bit, $hex or decimal
	            while (array_length(_target.instructions[0]) <= 12) array_push(_target.instructions[0], 0);
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][_idx] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 65535);
	            } else {
	                var _d = string_digits(_input);
	                _target.instructions[0][_idx] = (_d != "") ? clamp(real(_d), 0, 65535) : 0;
	            }
	        } else if (_idx == 15 || _idx == 17) {
	            // START / END VAR names from picker; "[clear]" empties
	            while (array_length(_target.instructions[0]) <= 17) array_push(_target.instructions[0], "");
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][_idx] = "";
	            } else {
	                _target.instructions[0][_idx] = string_upper(_input);
	            }
	        } else {
	            // X / Y / Colour — numeric clamped
	            var _digits = string_digits(_input);
	            if (_digits != "") {
	                var _val = real(_digits);
	                var _max = 15;
	                if (_idx == 1) _max = 39;
	                else if (_idx == 2) _max = 24;
	                _target.instructions[0][_idx] = clamp(_val, 0, _max);
	            } else {
	                _target.instructions[0][_idx] = 0;
	            }
	        }

	    // --- MACRO_PRINT_EXT ---
	    } else if (_target.node_type == "MACRO_PRINT_EXT") {
	        // instructions[0]: ["macro_print_ext", sx, sy, col, clr, src_mode,
	        //                    var_name, reg_id, fmt, align_h, align_v, pad]
	        if (_idx == 6) {
	            // VAR name from picker; "[clear]" empties it
	            while (array_length(_target.instructions[0]) <= 6) array_push(_target.instructions[0], "");
	            if (_input == "[clear]") {
	                _target.instructions[0][6] = "";
	            } else {
	                _target.instructions[0][6] = string_upper(_input);
	            }
	        } else {
	            // X / Y / Colour — numeric clamped (idx 1=sx, 2=sy, 3=col)
	            var _digits = string_digits(_input);
	            if (_digits != "") {
	                var _val = real(_digits);
	                var _max = 15;
	                if (_idx == 1) _max = 39;
	                else if (_idx == 2) _max = 24;
	                _target.instructions[0][_idx] = clamp(_val, 0, _max);
	            } else {
	                _target.instructions[0][_idx] = 0;
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_PLACE_CHAR ---
	    // [1] col_lit  [4] row_lit  [8] char_lit  [12] idx_lit
	    // [15] col_val [16] scr_base (hex)  [17] zp_base (hex)
	    // --- MACRO_CLR_SCREEN ---
	    // [1] scr_base (hex)  [2] fill (0-255)
	    } else if (_target.node_type == "MACRO_CLR_SCREEN") {
	        if (_idx == 1) {
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _hv = real(hex_to_decimal(string_upper(_clean)));
	            _target.instructions[0][1] = clamp(_hv, 0, 0xFFFF);
	        } else if (_idx == 2) {
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][2] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][2] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;
	            }
	        }
	        global.addresses_dirty = true;

	    } else if (_target.node_type == "MACRO_PLACE_CHAR") {
	        while (array_length(_target.instructions[0]) <= 17) {
	            var _pcn = array_length(_target.instructions[0]);
	            if (_pcn == 3 || _pcn == 6 || _pcn == 9 || _pcn == 10 || _pcn == 13) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 16 || _idx == 17) {
	            // SCR BASE / ZP BASE — always hex
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _hv = real(hex_to_decimal(string_upper(_clean)));
	            if (_idx == 16) {
	                _target.instructions[0][16] = clamp(_hv, 0, 0xFFFF);
	            } else {
	                // 4 consecutive ZP bytes needed — cap at $FC
	                _target.instructions[0][17] = clamp(_hv, 0x00, 0xFC);
	            }
	        } else if (_idx == 8 || _idx == 12) {
	            // CHAR literal / asset index — $xx or decimal, 0-255
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][_idx] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][_idx] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;
	            }
	        } else if (_idx == 1 || _idx == 4 || _idx == 15) {
	            // COL 0-39 / ROW 0-24 / COLOUR 0-15 — decimal
	            var _digits = string_digits(_input);
	            var _val = (_digits != "") ? real(_digits) : 0;
	            var _max = 15;
	            if (_idx == 1) {
	                _max = 39;
	            } else if (_idx == 4) {
	                _max = 24;
	            }
	            _target.instructions[0][_idx] = clamp(_val, 0, _max);
	        } else if (_idx == 3 || _idx == 6 || _idx == 9 || _idx == 10 || _idx == 13) {
	            // VAR / asset name from picker; "[clear]" empties
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][_idx] = "";
	            } else {
	                _target.instructions[0][_idx] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_MATH ---
	    // [1] op  [2] in_var  [3] operand_mode  [4] operand_lit(signed)
	    // [5] operand_var  [6] result_var
	    } else if (_target.node_type == "MACRO_MATH") {
	        while (array_length(_target.instructions[0]) <= 6) {
	            var _mmn = array_length(_target.instructions[0]);
	            if (_mmn == 2 || _mmn == 5 || _mmn == 6) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 4) {
	            // operand literal — signed: $hex is unsigned 0-65535, else [-]decimal
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][4] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 65535);
	            } else {
	                var _neg    = (string_char_at(_input, 1) == "-");
	                var _digits = string_digits(_input);
	                var _val    = (_digits != "") ? real(_digits) : 0;
	                if (_neg) _val = -_val;
	                _target.instructions[0][4] = clamp(_val, -32768, 65535);
	            }
	        } else if (_idx == 2 || _idx == 5 || _idx == 6) {
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][_idx] = "";
	            } else {
	                _target.instructions[0][_idx] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_GET_CHAR ---
	    // [1] col_lit  [4] row_lit  [7] dst_var  [9] dst_col_var
	    // [10] scr_base (hex)  [11] zp_base (hex)
	    } else if (_target.node_type == "MACRO_GET_CHAR") {
	        while (array_length(_target.instructions[0]) <= 11) {
	            var _gcn = array_length(_target.instructions[0]);
	            if (_gcn == 3 || _gcn == 6 || _gcn == 7 || _gcn == 9) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 10 || _idx == 11) {
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _hv = real(hex_to_decimal(string_upper(_clean)));
	            if (_idx == 10) {
	                _target.instructions[0][10] = clamp(_hv, 0, 0xFFFF);
	            } else {
	                _target.instructions[0][11] = clamp(_hv, 0x00, 0xFC);
	            }
	        } else if (_idx == 1 || _idx == 4) {
	            var _digits = string_digits(_input);
	            var _val = (_digits != "") ? real(_digits) : 0;
	            var _max = 39;
	            if (_idx == 4) {
	                _max = 24;
	            }
	            _target.instructions[0][_idx] = clamp(_val, 0, _max);
	        } else if (_idx == 3 || _idx == 6 || _idx == 7 || _idx == 9) {
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][_idx] = "";
	            } else {
	                _target.instructions[0][_idx] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- VOI64 MASTER ---
	    // [1] pitch Hz  [2] speed  [3] throat  [4] mouth  [5] zp_base (hex)
	    } else if (_target.node_type == "MACRO_VOI64_MASTER") {
	        while (array_length(_target.instructions[0]) <= 5) {
	            array_push(_target.instructions[0], 0);
	        }
	        if (_idx == 5) {
	            var _vz = (string_char_at(_input, 1) == "$")
	                    ? string_delete(_input, 1, 1) : _input;
	            // Nine consecutive bytes: pointer lo/hi, flags, three control
	            // shadows, and the range loop's cursor/end/temp. $F7 is the
	            // highest base that keeps all nine inside page zero — above
	            // that they wrap onto $00 and $01.
	            _target.instructions[0][5] = clamp(hex_to_decimal(_vz), 0x02, 0xF7);
	        } else if (_idx == 1) {
	            // Outside 50-400Hz it stops reading as a voice: too low and
	            // the sync source cannot excite the formant once per period,
	            // too high and the formants alias into each other.
	            _target.instructions[0][1] = clamp(real(string_digits(_input)), 50, 400);
	        } else {
	            _target.instructions[0][_idx] = clamp(real(string_digits(_input)), 0, 255);
	        }
	        global.addresses_dirty = true;

	    // --- VOI64 SAY ---
	    // [5] inline text  [6] asset name  [7..10] voice overrides
	    } else if (_target.node_type == "MACRO_VOI64_SAY") {
	        while (array_length(_target.instructions[0]) <= 16) {
	            var _vn = array_length(_target.instructions[0]);
	            if (_vn == 5 || _vn == 6 || _vn == 14 || _vn == 16) {
	                array_push(_target.instructions[0], "");
	            } else if (_vn >= 7 && _vn <= 10) {
	                array_push(_target.instructions[0], -1);
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 5 || _idx == 6) {
	            _target.instructions[0][_idx] = _input;
	        } else if (_idx == 14 || _idx == 16) {
	            _target.instructions[0][_idx] = string_upper(string_trim(_input));
	        } else if (_idx == 11 || _idx == 12) {
	            // Blank means "the end you did not specify" — 0 reads as line 1
	            // for FROM and as the last line for TO, so an untouched node
	            // speaks the whole asset.
	            var _lt = string_trim(_input);
	            if (_lt == "" || _lt == "-") {
	                _target.instructions[0][_idx] = 0;
	            } else {
	                _target.instructions[0][_idx] = clamp(real(string_digits(_lt)), 0, 9999);
	            }
	        } else if (_idx >= 7 && _idx <= 10) {
	            // Empty clears the override back to "inherit from master",
	            // which is what the node draws as a dash. Without this there
	            // would be no way to undo an override once one was typed.
	            var _vt = string_trim(_input);
	            if (_vt == "" || _vt == "-") {
	                _target.instructions[0][_idx] = -1;
	            } else if (_idx == 7) {
	                _target.instructions[0][7] = clamp(real(string_digits(_vt)), 50, 400);
	            } else {
	                _target.instructions[0][_idx] = clamp(real(string_digits(_vt)), 0, 255);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_RANDOM ---
	    // [2] freq (hex 16-bit)  [4] clamp_min  [5] clamp_max
	    // [7] dst_var  [8] zp_base (hex)
	    } else if (_target.node_type == "MACRO_RANDOM") {
	        while (array_length(_target.instructions[0]) <= 8) {
	            var _rnn = array_length(_target.instructions[0]);
	            if (_rnn == 7) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 2) {
	            // FREQ — hex 16-bit
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][2] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 0xFFFF);
	        } else if (_idx == 8) {
	            // ZP — hex, cap $FC (needs 2 consecutive bytes)
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][8] = clamp(real(hex_to_decimal(string_upper(_clean))), 0x00, 0xFE);
	        } else if (_idx == 4 || _idx == 5) {
	            // MIN / MAX — $xx or decimal, 0-255
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][_idx] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][_idx] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;
	            }
	        } else if (_idx == 7) {
	            // DEST VAR from picker; "[clear]" empties
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][7] = "";
	            } else {
	                _target.instructions[0][7] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_SID_SOUND ---
	    // [5] note (name / $hex -> 16-bit freq)  [8]wave [11]ad [14]sr ($hex/dec byte)
	    // [18] pw (12-bit)  [20] zp (hex byte)  [3/6/9/12/15/19] var pickers
	    } else if (_target.node_type == "MACRO_SID_SOUND") {
	        while (array_length(_target.instructions[0]) <= 28) {
	            var _sn = array_length(_target.instructions[0]);
	            if (_sn == 3 || _sn == 6 || _sn == 9 || _sn == 12 || _sn == 15 || _sn == 19
	             || _sn == 21 || _sn == 24 || _sn == 25 || _sn == 28) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 5) {
	            // NOTE — try note name, then $hex, then decimal -> 16-bit freq
	            var _raw = string_trim(_input);
	            var _fv  = -1;
	            if (string_char_at(_raw, 1) == "$") {
	                var _clean = string_delete(_raw, 1, 1);
	                _fv = real(hex_to_decimal(string_upper(_clean)));
	            } else {
	                _fv = scr_note_name_to_freq(_raw);
	                if (_fv < 0) {
	                    var _d = string_digits(_raw);
	                    _fv = (_d != "") ? real(_d) : 0;
	                }
	            }
	            _target.instructions[0][5] = clamp(_fv, 0, 65535);
	        } else if (_idx == 8 || _idx == 11 || _idx == 14) {
	            // WAVE / AD / SR — $hex or decimal, 0-255
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][_idx] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _d = string_digits(_input);
	                _target.instructions[0][_idx] = (_d != "") ? clamp(real(_d), 0, 255) : 0;
	            }
	        } else if (_idx == 18) {
	            // PW — $hex or decimal, 12-bit 0-4095
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][18] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 4095);
	            } else {
	                var _d = string_digits(_input);
	                _target.instructions[0][18] = (_d != "") ? clamp(real(_d), 0, 4095) : 0;
	            }
	        } else if (_idx == 20) {
	            // ZP — hex, 1 byte cap $FF
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][20] = clamp(real(hex_to_decimal(string_upper(_clean))), 0x00, 0xFF);
	        } else if (_idx == 23 || _idx == 27) {
	            // NOTE / WAVE INDEX — decimal 0-255 into the respective list
	            var _d = string_digits(_input);
	            _target.instructions[0][_idx] = (_d != "") ? clamp(real(_d), 0, 255) : 0;
	        } else if (_idx == 3 || _idx == 6 || _idx == 9 || _idx == 12 || _idx == 15
	                || _idx == 19 || _idx == 21 || _idx == 24 || _idx == 25 || _idx == 28) {
	            // VAR + asset pickers; "[clear]" empties
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][_idx] = "";
	            } else {
	                _target.instructions[0][_idx] = _input;
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_SID_SONG ---
	    // [1] asset name (picker)  [3] zp_base (hex byte)
	    // Slots 4/5 reserved for the byte/text table export work.
	    } else if (_target.node_type == "MACRO_SID_SONG") {
	        while (array_length(_target.instructions[0]) <= 5) {
	            var _sgn = array_length(_target.instructions[0]);
	            if (_sgn == 1 || _sgn == 5) {
	                array_push(_target.instructions[0], "");
	            } else if (_sgn == 4) {
	                array_push(_target.instructions[0], 2);   // hard restart frames
	            } else if (_sgn == 2) {
	                array_push(_target.instructions[0], 1);
	            } else if (_sgn == 3) {
	                array_push(_target.instructions[0], 0x03);
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 1) {
	            // SONG asset from picker; "[clear]" empties
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][1] = "";
	            } else {
	                _target.instructions[0][1] = _input;
	            }
	        } else if (_idx == 4) {
	            // HARD RESTART — frames of gate-off + dummy ADSR before a note.
	            // 0 = off. Above ~8 the delay is audible as sloppy timing.
	            var _d = string_digits(_input);
	            _target.instructions[0][4] = clamp((_d != "") ? real(_d) : 2, 0, 8);
	        } else if (_idx == 3) {
	            // ZP base — hex. The player needs 41 CONSECUTIVE bytes inside
	            // the free $03-$8F window: KERNAL owns $90-$FF, and $A0-$A2 is
	            // the jiffy clock the $EA31 IRQ tail rewrites every frame. So
	            // the block must start at $03 and end no later than $8F.
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][3] = clamp(real(hex_to_decimal(string_upper(_clean))), 0x03, 0x67);
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_SPR ---
	    } else if (_target.node_type == "MACRO_SPR") {
	        if (_idx == 1) {	   
	            _target.instructions[0][1] = _input;
			
	        } else {
	            // All other sprite fields — numeric
	            var _digits = string_digits(_input);
	            _target.instructions[0][_idx] = (_digits != "") ? real(_digits) : 0;
	        }

	    // --- MACRO_SID ---
	    } else if (_target.node_type == "MACRO_SID") {
	        if (_idx == 1) {
	            // SID address — hex input
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][1] = real(hex_to_decimal(string_upper(_clean)));
	        } else if (_idx == 4) {
	            // IRQ line — accept $xx or decimal, clamp 0-255
	            while (array_length(_target.instructions[0]) <= 4) array_push(_target.instructions[0], 0x60);
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][4] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][4] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0x60;
	            }
	        } else {
	            // Track — numeric
	            var _digits = string_digits(_input);
	            _target.instructions[0][_idx] = (_digits != "") ? real(_digits) : 0;
	        }
		// --- COPY_VAR ---
	    } else if (_target.node_type == "COPY_VAR") {
	        if (_idx == 1) {
	            // SRC name
	            if (_input == "[clear]") {
	                _target.instructions[0][1] = "";
	            } else {
	                _target.instructions[0][1] = string_upper(_input);
	            }
	        } else if (_idx == 2) {
	            // DST name
	            if (_input == "[clear]") {
	                _target.instructions[0][2] = "";
	            } else {
	                _target.instructions[0][2] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

		// --- VAR NODES (GET/SET/INC/DEC) ---
    } else if (_target.node_type == "GET_VAR" ||
               _target.node_type == "SET_VAR" ||
               _target.node_type == "INC_VAR" ||
               _target.node_type == "DEC_VAR") {
				   
		 if (_idx == 0) {
        _target.instructions[0][1] = string_upper(_input);
		} else if (_idx == 5 && _target.node_type == "GET_VAR") {
		    // GET_VAR asset offset literal — hex or decimal, clamp 0-255
		    while (array_length(_target.instructions[0]) < 7) array_push(_target.instructions[0], "");
		    var _clean = (string_char_at(_input, 1) == "$")
		               ? string_delete(_input, 1, 1) : _input;
		    if (string_char_at(_input, 1) == "$") {
		        _target.instructions[0][5] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
		    } else {
		        var _digits = string_digits(_input);
		        _target.instructions[0][5] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;
		    }
		    global.addresses_dirty = true;
		} else if (_idx == 2 && _target.node_type == "SET_VAR") {
			var _meta2 = scr_nloc_find_meta(string(_target.instructions[0][1]));
			    var _enc2  = (_meta2 != undefined && variable_struct_exists(_meta2, "encoding")) ? _meta2.encoding : "byte";
			    var _is_neg = (string_char_at(_input, 1) == "-");
			    var _stripped = _is_neg ? string_delete(_input, 1, 1) : _input;
			    if (string_char_at(_stripped, 1) == "$") {
			        var _clean = string_delete(_stripped, 1, 1);
			        var _val = real(hex_to_decimal(string_upper(_clean)));
			        if (_is_neg) _val = -_val;
			    } else {
			        var _digits = string_digits(_stripped);
			        var _val = (_digits != "") ? real(_digits) : 0;
			        if (_is_neg) _val = -_val;
			    }
			    if (_enc2 == "sbyte" && _val < 0) _val = 256 + _val;
			    _target.instructions[0][2] = _val;
				// Clamp to variable type max
				var _meta = scr_nloc_find_meta(string(_target.instructions[0][1]));
			    if (_meta != undefined) {
			        var _enc = variable_struct_exists(_meta, "encoding") ? _meta.encoding : "byte";
			        var _sz  = variable_struct_exists(_meta, "size")     ? _meta.size     : 1;
			        if (string_pos("bcd", _enc) > 0) {
			            _target.instructions[0][2] = clamp(_target.instructions[0][2], 0, 999999);
			        } else if (_sz == 2) {
			            _target.instructions[0][2] = clamp(_target.instructions[0][2], 0, 65535);
			        } else {
			            _target.instructions[0][2] = clamp(_target.instructions[0][2], 0, 255);
			        }
			    }
			}

	// --- NEW_STR ---
	    } else if (_target.node_type == "NEW_STR") {
	        if (_idx == 1) {
	            // Name field — same rules as the -78 rename path: case
	            // preserved, spaces -> underscores, UV_ prefix normalised
	            // to caps, duplicate-checked, references rewired.
	            var _raw = string_replace_all(string_trim(_input), " ", "_");
	            if (_raw != "") {
	                var _has_prefix = (string_upper(string_copy(_raw, 1, 3)) == "UV_");
	                var _new_name = _has_prefix
	                    ? ("UV_" + string_copy(_raw, 4, string_length(_raw) - 3))
	                    : ("UV_" + _raw);
	                var _old_name = string(_target.instructions[0][1]);

	                if (_new_name != _old_name) {
	                    var _dupe = false;
	                    with (obj_c64_node) {
	                        if (id == _target) continue;
	                        if (node_type != "NAMED_LOC" && node_type != "NEW_STR") continue;
	                        if (array_length(instructions) > 0 && array_length(instructions[0]) > 1
	                            && string(instructions[0][1]) == _new_name) {
	                            _dupe = true;
	                            break;
	                        }
	                    }
	                    if (_dupe) {
	                        scr_show_message("VAR NAME EXISTS:\n\n" + _new_name + "\n\nChoose a different name.");
	                    } else {
	                        var _refs = scr_find_var_references(_old_name, _target);
                        var _new_name_upper2 = string_upper(_new_name);
                        for (var _ri = 0; _ri < array_length(_refs); _ri++) {
                            var _rn = _refs[_ri].node;
                            if (!instance_exists(_rn)) continue;
                            var _rn_slots = _refs[_ri].slots;
                            with (_rn) {
                                for (var _si = 0; _si < array_length(_rn_slots); _si++) {
                                    instructions[0][_rn_slots[_si]] = _new_name_upper2;
                                }
                            }
                        }
	                        _target.instructions[0][1] = _new_name;
	                        _target.node_title = "UV STR";
	                        global.addresses_dirty = true;
	                        scr_c64_do_update_addresses();
	                        with (obj_c64_node) { last_overlap_check = false; overlap_check_dirty = true; }
	                    }
	                }
	            }
	        } else if (_idx == 3) {
	            // Inline text — store as-is, clamp to 40 chars
	            _target.instructions[0][3] = string_copy(_input, 1, min(string_length(_input), 40));
	        }
	        global.addresses_dirty = true;

	
	    // --- BANK_SWITCH ---
	    } else if (_target.node_type == "BANK_SWITCH") {
	        if (_idx == 1) {
	            // $01 value — hex or decimal, clamp 0-255
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _v01 = 0;
	            if (string_char_at(_input, 1) == "$") {
	                _v01 = real(hex_to_decimal(string_upper(_clean)));
	            } else {
	                var _digits = string_digits(_input);
	                _v01 = (_digits != "") ? real(_digits) : 0x37;
	            }
	            _v01 = clamp(_v01, 0, 255);
	            _target.instructions[0][1] = _v01;

	            // Snap mode_index to matching named mode, else RAW (-1)
	            var _mode_vals = [0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37];
	            var _found_idx = -1;
	            for (var _mvi = 0; _mvi < array_length(_mode_vals); _mvi++) {
	                if (_mode_vals[_mvi] == _v01) {
	                    _found_idx = _mvi;
	                    break;
	                }
	            }
	            _target.instructions[0][4] = _found_idx;
	            global.addresses_dirty = true;
	        }

	    // --- MACRO_REU ---
	    // idx 2 = C64 addr (hex, 16-bit), idx 3 = REU addr (hex, 16-bit),
	    // idx 4 = bank (decimal, 0-255), idx 5 = length (hex, 16-bit),
	    // idx 14 = INDEXED WORD-mode ZP scratch base (hex, 8-bit).
	    } else if (_target.node_type == "MACRO_REU") {
	        while (array_length(_target.instructions[0]) < 9) { array_push(_target.instructions[0], 0); }
	        if (_idx == 2 || _idx == 3 || _idx == 5) {
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _val = 0;
	            if (string_char_at(_input, 1) == "$") {
	                _val = real(hex_to_decimal(string_upper(_clean)));
	            } else {
	                var _digits = string_digits(_input);
	                _val = (_digits != "") ? real(_digits) : 0;
	            }
	            _target.instructions[0][_idx] = clamp(_val, 0, 0xFFFF);
	        } else if (_idx == 4) {
	            var _digits = string_digits(_input);
	            _target.instructions[0][4] = clamp((_digits != "") ? real(_digits) : 0, 0, 255);
	        } else if (_idx == 14) {
	            var _zp_clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            var _zp_val = 0;
	            if (string_char_at(_input, 1) == "$") {
	                _zp_val = real(hex_to_decimal(string_upper(_zp_clean)));
	            } else {
	                var _zp_digits = string_digits(_input);
	                _zp_val = (_zp_digits != "") ? real(_zp_digits) : 0;
	            }
	            _target.instructions[0][14] = clamp(_zp_val, 0, 0xFF);
	        }
	        global.addresses_dirty = true;

	    // --- COND_IF ---
	    } else if (_target.node_type == "COND_IF_WORD") {
	        if (instance_exists(obj_workspace_manager)) {
	            obj_workspace_manager.flow_overlay_dirty = true;
	        }
	        if (_idx == 2) {
	            // cmp_value — 16-bit; $ prefix = hex, bare number = decimal
	            var _val = 0;
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _val = real(hex_to_decimal(string_upper(_clean)));
	            } else {
	                var _digits = string_digits(_input);
	                _val = (_digits != "") ? real(_digits) : 0;
	            }
	            _target.instructions[0][2] = clamp(_val, 0, 65535);
	        } else if (_idx == 3) {
	            // branch_target — label string
	            _target.instructions[0][3] = _input;
	        } else if (_idx == 5) {
	            // cmp_var — VAR picker commit; "[clear]" resets to literal mode
	            while (array_length(_target.instructions[0]) <= 5) array_push(_target.instructions[0], "");
	            if (_input == "[clear]") {
	                _target.instructions[0][5] = "";
	            } else {
	                _target.instructions[0][5] = string_upper(_input);
	            }
	        }

	    } else if (_target.node_type == "COND_IF") {
	        if (instance_exists(obj_workspace_manager)) {
	            obj_workspace_manager.flow_overlay_dirty = true;
	        }
	        if (_idx == 2) {
	            // cmp_value — $ prefix = hex, bare number = always decimal
	            var _val = 0;
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _val = real(hex_to_decimal(string_upper(_clean)));
	            } else {
	                var _digits = string_digits(_input);
	                _val = (_digits != "") ? real(_digits) : 0;
	            }
	            _target.instructions[0][2] = clamp(_val, 0, 255);
	        } else if (_idx == 3) {
	            // branch_target — label string
	            _target.instructions[0][3] = _input;
	        } else if (_idx == 5) {
	            // cmp_var — VAR picker commit; "[clear]" resets to literal mode
	            while (array_length(_target.instructions[0]) <= 5) array_push(_target.instructions[0], "");
	            if (_input == "[clear]") {
	                _target.instructions[0][5] = "";
	            } else {
	                _target.instructions[0][5] = string_upper(_input);
	            }
	        }
		
		
	// --- MACRO_COLLISION ---
		} else if (_target.node_type == "MACRO_COLLISION") {
	        // Backfill new fields if missing
	        while (array_length(_target.instructions[0]) < 7) array_push(_target.instructions[0], 0);
	        if (!is_array(_target.instructions[0][6])) _target.instructions[0][6] = array_create(256, 0);
	        while (array_length(_target.instructions[0]) < 8) array_push(_target.instructions[0], "");
	        while (array_length(_target.instructions[0]) < 9) array_push(_target.instructions[0], "");
	        while (array_length(_target.instructions[0]) < 10) array_push(_target.instructions[0], "");
	        if (_idx == 1) {
	            // slot_mask — hex or decimal byte
	            var _clean = (string_char_at(_input, 1) == "$")
	                       ? string_delete(_input, 1, 1) : _input;
	            _target.instructions[0][1] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	        } else if (_idx == 2) {
	            // type: 0/1/2
	            var _d = string_digits(_input);
	            _target.instructions[0][2] = clamp((_d != "") ? real(_d) : 0, 0, 2);
	        } else if (_idx == 3) {
	            _target.instructions[0][3] = _input; // jsr label (GOTO / main)
	        } else if (_idx == 4) {
	            var _d = string_digits(_input);
	            _target.instructions[0][4] = clamp((_d != "") ? real(_d) : 0, 0, 1); // mode
	        } else if (_idx == 7) {
	            _target.instructions[0][7] = _input; // jsr_wall
	        } else if (_idx == 8) {
	            _target.instructions[0][8] = _input; // jsr_water
	        } else if (_idx == 9) {
	            _target.instructions[0][9] = _input; // jsr_other
	        }

	// --- MACRO_ANIM ---
	} else if (_target.node_type == "MACRO_ANIM") {
	        while (array_length(_target.instructions[0]) < 36) array_push(_target.instructions[0], "");
	        if (_idx == 1) {
	            var _d = string_digits(_input);
	            _target.instructions[0][1] = clamp((_d != "") ? real(_d) : 8, 1, 255);
	        } else if (_idx >= 2 && _idx <= 9) {
	            _target.instructions[0][_idx] = _input; // frame offsets
	        } else if (_idx >= 11 && _idx <= 18) {
	            _target.instructions[0][_idx] = _input; // X deltas
	        } else if (_idx >= 19 && _idx <= 26) {
	            _target.instructions[0][_idx] = _input; // Y deltas
	        } else if (_idx >= 27 && _idx <= 34) {
	            _target.instructions[0][_idx] = _input; // 9th bit per slot
	        } else if (_idx == 35) {
	            // DONE VAR name from picker; "[clear]" empties it
	            if (_input == "[clear]") {
	                _target.instructions[0][35] = "";
	            } else {
	                _target.instructions[0][35] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_BMP ---
	    } else if (_target.node_type == "MACRO_BMP") {
	        // All BMP fields are hex addresses
	        var _clean = (string_char_at(_input, 1) == "$")
	                   ? string_delete(_input, 1, 1) : _input;
	        _target.instructions[0][_idx] = real(hex_to_decimal(string_upper(_clean)));
		
	// --- MACRO_IRQ ---
	    } else if (_target.node_type == "MACRO_IRQ") {
	        if (_idx == 1) {
	            // Raster line: accept $xx or decimal, clamp 0-255
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][1] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][1] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0x60;
	            }
	        } else if (_idx == 3) {
	            // Asset name — plain string
	            _target.instructions[0][3] = _input;
			} else if (_idx == 4) {
	            // Alias — plain string, strip spaces
	            _target.instructions[0][4] = string_replace_all(_input, " ", "_");
	        } else if (_idx == 5) {
	            // Call label — plain string
	            _target.instructions[0][5] = string_replace_all(_input, " ", "_");
	        }

	    // --- MACRO_TRACK ---
	    } else if (_target.node_type == "MACRO_TRACK") {
	        var _digits = string_digits(_input);
	        _target.instructions[0][1] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;

	    // --- MACRO_DISPLAY ---
	    } else if (_target.node_type == "MACRO_DISPLAY") {
	        while (array_length(_target.instructions[0]) < 2) array_push(_target.instructions[0], 1);
	        if (_idx == 1) {
	            var _digits = string_digits(_input);
	            var _dv = 1;
	            if (_digits != "") {
	                _dv = real(_digits);
	            }
	            _target.instructions[0][1] = clamp(_dv, 0, 1);
	            global.addresses_dirty = true;
	        }

	    // --- MACRO_NOP_REPEAT ---
	    } else if (_target.node_type == "MACRO_NOP_REPEAT") {
	        while (array_length(_target.instructions[0]) < 2) {
	            array_push(_target.instructions[0], 0);
	        }
	        if (_idx == 1) {
	            // NOP COUNT - decimal, 0-255. Each NOP is 1 byte / 2 cycles.
	            var _nr_digits = string_digits(_input);
	            var _nr_val = 0;
	            if (_nr_digits != "") {
	                _nr_val = real(_nr_digits);
	            }
	            _target.instructions[0][1] = clamp(_nr_val, 0, 255);
	            global.addresses_dirty = true;
	        }

	    // --- MACRO_WAIT ---
	    } else if (_target.node_type == "MACRO_WAIT") {
	        while (array_length(_target.instructions[0]) < 4) {
	            var _wcn = array_length(_target.instructions[0]);
	            if (_wcn == 3) {
	                array_push(_target.instructions[0], "");
	            } else {
	                array_push(_target.instructions[0], 0);
	            }
	        }
	        if (_idx == 1) {
	            // FRAME COUNT — $xx or decimal, 1-255 (counter lives in X)
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][1] = clamp(real(hex_to_decimal(string_upper(_clean))), 1, 255);
	            } else {
	                var _digits = string_digits(_input);
	                var _fv = 1;
	                if (_digits != "") {
	                    _fv = real(_digits);
	                }
	                _target.instructions[0][1] = clamp(_fv, 1, 255);
	            }
	        } else if (_idx == 3) {
	            // VAR name from picker; "[clear]" reverts to literal mode
	            if (_input == "[clear]" || _input == "") {
	                _target.instructions[0][3] = "";
	                _target.instructions[0][2] = 0;
	            } else {
	                _target.instructions[0][3] = string_upper(_input);
	            }
	        }
	        global.addresses_dirty = true;

	    // --- MACRO_VWAIT ---
	    } else if (_target.node_type == "MACRO_VWAIT") {
	        // Ensure slots exist
	        while (array_length(_target.instructions[0]) < 4) array_push(_target.instructions[0], 0);
	        if (!is_string(_target.instructions[0][3])) _target.instructions[0][3] = "";

	        if (_idx == 0 || _idx == 1) {
	            // Literal raster line — accept $xx or decimal, clamp 0-255
	            if (string_char_at(_input, 1) == "$") {
	                var _clean = string_delete(_input, 1, 1);
	                _target.instructions[0][1] = clamp(real(hex_to_decimal(string_upper(_clean))), 0, 255);
	            } else {
	                var _digits = string_digits(_input);
	                _target.instructions[0][1] = (_digits != "") ? clamp(real(_digits), 0, 255) : 0;
	            }
	        } else if (_idx == 3) {
	            // Var name from picker; "[clear]" reverts to literal mode
	            if (_input == "[clear]") {
	                _target.instructions[0][3] = "";
	                _target.instructions[0][2] = 0;
	            } else {
	                _target.instructions[0][3] = string_upper(_input);
	            }
	            global.addresses_dirty = true;
	        }

	    // --- NORMAL / everything else ---
	    } else {
	        var _inst_name = (array_length(_target.instructions) > _idx)
	                       ? string_lower(_target.instructions[_idx][0]) : "";
	        var _is_branch = (string_char_at(_inst_name, 1) == "b" && string_length(_inst_name) == 3);
	        var _is_jump   = (string_pos("jmp", _inst_name) > 0 || string_pos("jsr", _inst_name) > 0);

	        if (_is_branch || _is_jump) {
	            // Branch / jump — store as label string
	            _target.instructions[_idx][1] = _input;
	            if (array_length(_target.instructions[_idx]) > 2) {
	                _target.instructions[_idx][2] = _input;
	            }
	} else {
	            // Standard operand — hex or decimal
	            // Determine byte cap from opcode size: size 2 = byte (0-255), size 3 = word (0-65535)
	            var _opcodes = obj_opCodeManager.opcode_info;
	            var _op_size  = variable_struct_exists(_opcodes, _inst_name) ? _opcodes[$ _inst_name][0] : 2;
	            var _is_byte  = (_op_size <= 2); // size 2 = 1 operand byte; size 3 = 2 operand bytes
	            var _max_val  = _is_byte ? 255 : 65535;

	            var _val = 0;
	            if (string_char_at(_input, 1) == "$") {
	                // Hex input — always parse as hex regardless of display mode
	                var _clean_hex = string_delete(_input, 1, 1);
	                _val = real(hex_to_decimal(string_upper(_clean_hex)));
            
	            } else {
	                // Decimal mode
	                var _digits = string_digits(_input);
	                _val = (_digits != "") ? real(_digits) : 0;
	            }
	            _target.instructions[_idx][1] = clamp(_val, 0, _max_val);
	        }
	    }

	    // Post-commit syncs
	    if (_target.node_type == "MACRO_SPR") scr_macro_spr_sync(_target);
	    if (_target.node_type == "MACRO_SID") scr_macro_sid_sync(_target);
	}
