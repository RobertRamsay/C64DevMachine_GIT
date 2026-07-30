function scr_node_step_new_str() {
    if (!mouse_check_button_pressed(mb_left)) return;

    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);

    var _px   = x + 8;
    var _ly0  = y + 24 + 4;
    var _lh   = 16;
    var _x1_g = (_px              - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16 - _cam_x) / _cam_zoom;

    var _row0_g = (_ly0           - _cam_y) / _cam_zoom; // name row
    var _row1_g = (_ly0 + _lh     - _cam_y) / _cam_zoom; // src toggle
    var _row2_g = (_ly0 + _lh * 2 - _cam_y) / _cam_zoom; // content
    var _lh_g   = _lh / _cam_zoom;

    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);

    // Row 0 — name click: open text input for instructions[0][1]
    if (_in_col && _mgy >= _row0_g && _mgy < _row0_g + _lh_g) {
        while (array_length(instructions[0]) <= 1) array_push(instructions[0], "UV_STR");
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(instructions[0][1]);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

    // Row 1 — toggle inline/asset (instructions[0][4])
    if (_in_col && _mgy >= _row1_g && _mgy < _row1_g + _lh_g) {
        while (array_length(instructions[0]) <= 4) array_push(instructions[0], 0);
        var _cur = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0;
        instructions[0][4] = (_cur == 0) ? 1 : 0;
        global.addresses_dirty = true;
        return;
    }

    // Row 2 — inline text entry OR asset cycle
    if (_in_col && _mgy >= _row2_g && _mgy < _row2_g + _lh_g) {
        var _use_as = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
        if (_use_as == 0) {
            while (array_length(instructions[0]) <= 3) array_push(instructions[0], "HELLO WORLD ");
            obj_workspace_manager.input_target_node    = id;
            obj_workspace_manager.input_target_index   = 3;
            obj_workspace_manager.current_input_string = string(instructions[0][3]);
            obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
            obj_workspace_manager.is_entering_text     = true;
        } else {
            // Cycle through TEXT_DATA assets
            if (instance_exists(obj_asset_manager)) {
                var _am    = obj_asset_manager;
                var _names = [];
                for (var _ti = 0; _ti < ds_list_size(_am.asset_list); _ti++) {
                    var _ta = ds_list_find_value(_am.asset_list, _ti);
                    if (_ta.type == "TEXT_DATA") array_push(_names, _ta.name);
                }
                if (array_length(_names) > 0) {
                    while (array_length(instructions[0]) <= 5) array_push(instructions[0], "");
                    var _cur_name = string(instructions[0][5]);
                    var _idx = 0;
                    for (var _ni = 0; _ni < array_length(_names); _ni++) {
                        if (_names[_ni] == _cur_name) { _idx = (_ni + 1) mod array_length(_names); break; }
                    }
                    instructions[0][5] = _names[_idx];
                    
                    // Instantly sync the Data Address to match the newly chosen asset
                    for (var _ti = 0; _ti < ds_list_size(_am.asset_list); _ti++) {
                        var _ta = ds_list_find_value(_am.asset_list, _ti);
                        if (_ta.type == "TEXT_DATA" && _ta.name == instructions[0][5]) {
                            if (variable_struct_exists(_ta.meta, "address")) {
                                instructions[0][2] = _ta.meta.address;
                            }
                            break;
                        }
                    }
                    scr_c64_update_addresses();
                }
            }
        }
        return;
    }
}