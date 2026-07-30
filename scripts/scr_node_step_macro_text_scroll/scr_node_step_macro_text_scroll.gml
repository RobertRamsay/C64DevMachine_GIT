function scr_node_step_macro_text_scroll() {
    if (!mouse_check_button_pressed(mb_left)) return;

    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);

    // GUI-space row positions — mirrors draw function _ly sequence exactly.
    // Draw starts at _ly = _y + 24 + 4, increments by _lh = 18 per row.
    var _px  = x + 8;
    var _ly0 = y + 28
    var _lh  = 12;

	
    // If no SID connected, warning banner adds one extra row at the top
    var _use_sid_step = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _use_sid_step = 1; break; }
    }
    if (_use_sid_step == 0) {
        _ly0 += _lh;
    }

    var _x1_g = (_px               - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16  - _cam_x) / _cam_zoom;
    var _lh_g = _lh / _cam_zoom;


	
	var _ry = [
        (_ly0           - _cam_y) / _cam_zoom,  // row 0: SCROLL ROW
        (_ly0 + _lh     - _cam_y) / _cam_zoom,  // row 1: COLOUR
        (_ly0 + _lh * 2 - _cam_y) / _cam_zoom,  // row 2: SPEED
        (_ly0 + _lh * 3 - _cam_y) / _cam_zoom,  // row 3: DATA ADDR
        (_ly0 + _lh * 4 - _cam_y) / _cam_zoom,  // row 4: CHARSET ADDR
        (_ly0 + _lh * 5 - _cam_y) / _cam_zoom,  // row 5: TEXT SRC
        (_ly0 + _lh * 6 - _cam_y) / _cam_zoom,  // row 6: TEXT/ASSET CONTENT
        (_ly0 + _lh * 7 - _cam_y) / _cam_zoom,  // row 7: PRE-NOP
        (_ly0 + _lh * 8 - _cam_y) / _cam_zoom,  // row 8: POST-NOP
    ];

    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);

    // ROW 0 — SCROLL ROW: numeric entry (index [1])
    if (_in_col && _mgy >= _ry[0] && _mgy < _ry[0] + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][1]) ? real(instructions[0][1]) : 23);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

    // ROW 1 — COLOUR: cycle 0→15→0 (index [2])
    if (_in_col && _mgy >= _ry[1] && _mgy < _ry[1] + _lh_g) {
        while (array_length(instructions[0]) <= 2) array_push(instructions[0], 1);
        var _cur = is_real(instructions[0][2]) ? real(instructions[0][2]) : 1;
        instructions[0][2] = (_cur + 1) mod 16;
        scr_c64_update_addresses();
        return;
    }

    // ROW 2 — SPEED: cycle 1→7→1 (index [3])
    if (_in_col && _mgy >= _ry[2] && _mgy < _ry[2] + _lh_g) {
        while (array_length(instructions[0]) <= 3) array_push(instructions[0], 2);
        var _spd = is_real(instructions[0][3]) ? real(instructions[0][3]) : 2;
        instructions[0][3] = (_spd mod 7) + 1;
        scr_c64_update_addresses();
        return;
    }

    // ROW 3 — DIRECTION removed

    // ROW 3 — DATA ADDR: numeric entry (index [5]), locked in asset mode
    var _text_src_step = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
    if (_text_src_step == 0 && _in_col && _mgy >= _ry[3] && _mgy < _ry[3] + _lh_g) {
        while (array_length(instructions[0]) <= 5) array_push(instructions[0], 0xC000);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 5;
		var _addr_val = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0xC000;
		        if (global.use_hex_display) {
		            var _ah = string_upper(decimal_to_hex(_addr_val));
		            while (string_length(_ah) < 4) _ah = "0" + _ah;
		            obj_workspace_manager.current_input_string = "$" + _ah;
		        } else {
		            obj_workspace_manager.current_input_string = string(_addr_val);
		        }
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

// ROW 4 — CHARSET ASSET: Trigger Picker (index [13])
    if (_in_col && _mgy >= _ry[4] && _mgy < _ry[4] + _lh_g) {
        if (instance_exists(obj_asset_manager)) {
            obj_asset_manager.chr_picker_open = true;
            obj_asset_manager.chr_picker_node = id;
            // Send a target index so the picker knows exactly where to save the name
            obj_asset_manager.chr_picker_target_index = 13;
        }
        return;
    }

// ROW 5 — TEXT SRC: toggle inline/asset (index [9])
    if (_in_col && _mgy >= _ry[5] && _mgy < _ry[5] + _lh_g) {
        while (array_length(instructions[0]) <= 9) array_push(instructions[0], 0);
        var _cur = is_real(instructions[0][9]) ? real(instructions[0][9]) : 0;
        instructions[0][9] = (_cur == 0) ? 1 : 0;
        scr_c64_update_addresses();
        return;
    }

    // ROW 6 — inline text entry OR asset cycle (index [6] / [10])
    if (_in_col && _mgy >= _ry[6] && _mgy < _ry[6] + _lh_g) {
        var _src = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
        if (_src == 0) {
            keyboard_string = "";
            while (array_length(instructions[0]) <= 6) array_push(instructions[0], "HELLO WORLD ");
            obj_workspace_manager.input_target_node    = id;
            obj_workspace_manager.input_target_index   = 6;
            obj_workspace_manager.current_input_string = string(instructions[0][6]);
            obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
            obj_workspace_manager.is_entering_text     = true;
        } else {
            if (instance_exists(obj_asset_manager)) {
                var _am    = obj_asset_manager;
                var _names = [];
                for (var _ti = 0; _ti < ds_list_size(_am.asset_list); _ti++) {
                    var _ta = ds_list_find_value(_am.asset_list, _ti);
                    if (_ta.type == "TEXT_DATA") array_push(_names, _ta.name);
                }
                if (array_length(_names) > 0) {
                    while (array_length(instructions[0]) <= 10) array_push(instructions[0], "");
                    var _cur_name = string(instructions[0][10]);
                    var _idx = 0;
                    for (var _ni = 0; _ni < array_length(_names); _ni++) {
                        if (_names[_ni] == _cur_name) { _idx = (_ni + 1) mod array_length(_names); break; }
                    }
                    instructions[0][10] = _names[_idx];
                    scr_c64_update_addresses();
                }
            }
        }
        return;
    }

// ROW 7 — PRE-NOP (index [7])
    if (_in_col && _mgy >= _ry[7] && _mgy < _ry[7] + _lh_g) {
        while (array_length(instructions[0]) <= 7) array_push(instructions[0], 6);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 7;
        obj_workspace_manager.current_input_string = string(real(instructions[0][7]));
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

// ROW 8 — POST-NOP (index [8])
    if (_in_col && _mgy >= _ry[8] && _mgy < _ry[8] + _lh_g) {
        while (array_length(instructions[0]) <= 8) array_push(instructions[0], 27);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 8;
        obj_workspace_manager.current_input_string = string(real(instructions[0][8]));
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
	
// ROW 9 — JSR MODE: checkbox toggle (index [11])
    var _jchk_x  = (_px - _cam_x) / _cam_zoom;
    var _jchk_y  = (_ly0 + _lh * 9 + 2 - _cam_y) / _cam_zoom;
    var _jchk_sz = 14.0 / _cam_zoom;
    var _jlbl_w  = 100.0 / _cam_zoom;
    if (_mgx >= _jchk_x && _mgx <= _jchk_x + _jchk_sz + _jlbl_w &&
        _mgy >= _jchk_y && _mgy <= _jchk_y + _jchk_sz) {
        while (array_length(instructions[0]) <= 11) array_push(instructions[0], 0);
        var _cur = is_real(instructions[0][11]) ? real(instructions[0][11]) : 0;
        instructions[0][11] = (_cur == 1) ? 0 : 1;
        scr_c64_update_addresses();
        return;
    }


// ALIAS row — click to edit
    var _jsr_mode_step = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
    var _alias_row_offset = (_jsr_mode_step == 1) ? 11 : 10;
    var _alias_ry = (_ly0 + _lh * _alias_row_offset - _cam_y) / _cam_zoom;
    if (_in_col && _mgy >= _alias_ry && _mgy < _alias_ry + _lh_g) {
        var _cur_alias = (array_length(instructions[0]) > 12 && is_string(instructions[0][12]) && string(instructions[0][12]) != "") ? string(instructions[0][12]) : ("ts" + string(real(id)));
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 12;
        obj_workspace_manager.current_input_string = _cur_alias;
        obj_workspace_manager.cursor_pos           = string_length(_cur_alias);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
	
}
