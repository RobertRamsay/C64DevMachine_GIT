function scr_node_step_macro_scroll() {
    // Auto-clear USE SID IRQ if no SID node present
    var _sid_check = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID") { _sid_check = true; break; }
    }
if (!_sid_check && array_length(instructions[0]) > 4 && instructions[0][4] == 1) {
        instructions[0][4] = 0;
        scr_c64_update_addresses();
    }
    // Row count is no longer capped by SID presence — with the IRQ split,
    // SID enables a steady HUD rather than limiting scroll rows. Only the
    // physical screen height (25) bounds it; clamping happens on entry below.
    if (!mouse_check_button_pressed(mb_left)) return;
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);
    // GUI-space row positions — must mirror _ly sequence in draw function exactly.
    // Draw starts at _ly = _y + 24 + 4, increments by _lh = 18 per row.
    var _px  = x + 8;
    var _ly0 = y + 24 + 4;  // ROW 0: START ROW
    var _lh  = 18;
    var _x1_g = (_px           - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16 - _cam_x) / _cam_zoom;
    var _lh_g = _lh / _cam_zoom;
var _ry = [
        (_ly0           - _cam_y) / _cam_zoom,  // row 0: START ROW
        (_ly0 + _lh     - _cam_y) / _cam_zoom,  // row 1: ROW COUNT
        (_ly0 + _lh * 2 - _cam_y) / _cam_zoom,  // row 2: COLOUR MODE
        (_ly0 + _lh * 3 - _cam_y) / _cam_zoom,  // row 3: SPEED
        (_ly0 + _lh * 4 - _cam_y) / _cam_zoom,  // row 4: DIRECTION
        (_ly0 + _lh * 5 - _cam_y) / _cam_zoom,  // row 5: USE SID IRQ
    ];
    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);
    // ROW 0 — START ROW: open text entry for index [1]
    if (_in_col && _mgy >= _ry[0] && _mgy < _ry[0] + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][1]) ? real(instructions[0][1]) : 4);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
// ROW 1 — ROW COUNT: open text entry for index [2]
    if (_in_col && _mgy >= _ry[1] && _mgy < _ry[1] + _lh_g) {

        var _max_rows_step = 25;
        var _cur_rows = is_real(instructions[0][2]) ? real(instructions[0][2]) : 16;
        instructions[0][2] = clamp(_cur_rows, 1, _max_rows_step);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 2;
        obj_workspace_manager.current_input_string = string(instructions[0][2]);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
    // ROW 2 — COLOUR MODE: cycle 0→1→2→0 (index [3])
    if (_in_col && _mgy >= _ry[2] && _mgy < _ry[2] + _lh_g) {
        var _cur = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 1;
        instructions[0][3] = (_cur + 1) mod 3;
        scr_c64_update_addresses();
        return;
    }

    // Rows below JSR LEFT/RIGHT (rows 4,5) — SOURCE at row 6, TILESET at
    // row 7, MAP IDX at row 8, BASE ADDR at row 9. Must mirror the draw
    // function's _ly sequence.
    var _ly_source    = (_ly0 + _lh * 6 - _cam_y) / _cam_zoom;
    var _ly_tileset   = (_ly0 + _lh * 7 - _cam_y) / _cam_zoom;
    var _ly_mapidx    = (_ly0 + _lh * 8 - _cam_y) / _cam_zoom;
    var _ly_baseaddr  = (_ly0 + _lh * 9 - _cam_y) / _cam_zoom;

    // Pad missing slots individually with their real defaults — never
    // blind-zero index [9] (base_addr), a real $0000 target silently
    // drops every byte of the flattened char plane at assemble time.
    if (array_length(instructions[0]) < 7)  { array_push(instructions[0], 0); }
    if (array_length(instructions[0]) < 8)  { array_push(instructions[0], ""); }
    if (array_length(instructions[0]) < 9)  { array_push(instructions[0], 0); }
    if (array_length(instructions[0]) < 10) { array_push(instructions[0], 0xA000); }
    if (array_length(instructions[0]) < 11) { array_push(instructions[0], 1); }
    var _mm_src_mode = is_real(instructions[0][6]) ? real(instructions[0][6]) : 0;

    // CLR UNUSED sits right after whatever the draw function drew last —
    // row 7 is one past SOURCE's own row (6), +3 when META_TILESET is
    // active, +1 more if that tileset carries a stamp override. Must
    // mirror draw exactly.
    var _mm_clamp_row_offset = 7;
    if (_mm_src_mode == 1) {
        _mm_clamp_row_offset += 3;
        var _mm_tileset_name_chk = is_string(instructions[0][7]) ? string(instructions[0][7]) : "";
        if (_mm_tileset_name_chk != "" && instance_exists(obj_asset_manager)) {
            var _mm_am_chk = obj_asset_manager;
            for (var _mm_ai_chk = 0; _mm_ai_chk < ds_list_size(_mm_am_chk.asset_list); _mm_ai_chk++) {
                var _mm_a_chk = ds_list_find_value(_mm_am_chk.asset_list, _mm_ai_chk);
                if (_mm_a_chk.type == "META_TILESET" && _mm_a_chk.name == _mm_tileset_name_chk) {
                    if (variable_struct_exists(_mm_a_chk.meta, "stamp_override")) {
                        for (var _mm_oi_chk = 0; _mm_oi_chk < array_length(_mm_a_chk.meta.stamp_override); _mm_oi_chk++) {
                            if (_mm_a_chk.meta.stamp_override[_mm_oi_chk] != 0x80) {
                                _mm_clamp_row_offset += 1;
                                break;
                            }
                        }
                    }
                    break;
                }
            }
        }
    }
    var _ly_clamp = (_ly0 + _lh * _mm_clamp_row_offset - _cam_y) / _cam_zoom;

    // SOURCE row — toggle MAP_DATA <-> META_TILESET, index [6]
    if (_in_col && _mgy >= _ly_source && _mgy < _ly_source + _lh_g) {
        if (_mm_src_mode == 0) {
            instructions[0][6] = 1;
        } else {
            instructions[0][6] = 0;
        }
        instructions[0][8] = 0; // reset map index on source change
        height_dirty = true;
        scr_c64_update_addresses();
        return;
    }

    // CLR UNUSED row — toggle blank-excluded-rows pass, index [10].
    // Always shown regardless of source mode.
    if (_in_col && _mgy >= _ly_clamp && _mgy < _ly_clamp + _lh_g) {
        var _mm_cur_clamp = is_real(instructions[0][10]) ? real(instructions[0][10]) : 1;
        if (_mm_cur_clamp == 0) {
            instructions[0][10] = 1;
        } else {
            instructions[0][10] = 0;
        }
        scr_c64_update_addresses();
        return;
    }

    if (_mm_src_mode == 1) {
        // TILESET row — open the shared META_TILESET picker targeting [7]/[8]
        if (_in_col && _mgy >= _ly_tileset && _mgy < _ly_tileset + _lh_g) {
            with (obj_asset_manager) {
                metamap_picker_open       = true;
                metamap_picker_node       = other.id;
                metamap_picker_hover      = -1;
                metamap_picker_name_idx   = 7;
                metamap_picker_mapidx_idx = 8;
            }
            return;
        }

        // MAP IDX row — open text entry for index [8]
        if (_in_col && _mgy >= _ly_mapidx && _mgy < _ly_mapidx + _lh_g) {
            obj_workspace_manager.input_target_node    = id;
            obj_workspace_manager.input_target_index   = 8;
            obj_workspace_manager.current_input_string = string(is_real(instructions[0][8]) ? real(instructions[0][8]) : 0);
            obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
            obj_workspace_manager.is_entering_text     = true;
            return;
        }

        // BASE ADDR row — open text entry for index [9] (plain 4-digit hex,
        // zero-padded, no $ — matches the convention other hex-address
        // fields in this codebase use for their modal pre-fill)
        if (_in_col && _mgy >= _ly_baseaddr && _mgy < _ly_baseaddr + _lh_g) {
            var _mm_cur_addr = is_real(instructions[0][9]) ? real(instructions[0][9]) : 0xA000;
            var _mm_hex      = string_upper(decimal_to_hex(_mm_cur_addr));
            while (string_length(_mm_hex) < 4) {
                _mm_hex = "0" + _mm_hex;
            }
            obj_workspace_manager.input_target_node    = id;
            obj_workspace_manager.input_target_index   = 9;
            obj_workspace_manager.current_input_string = _mm_hex;
            obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
            obj_workspace_manager.is_entering_text     = true;
            return;
        }
    }
}