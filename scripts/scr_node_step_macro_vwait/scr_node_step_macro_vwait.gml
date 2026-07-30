function scr_node_step_macro_vwait(_draw_x) {
    // Ensure slots exist
    while (array_length(instructions[0]) < 4) {
        array_push(instructions[0], 0);
    }
    if (!is_string(instructions[0][3])) instructions[0][3] = "";

    var _use_var  = real(instructions[0][2]);

    // Geometry — must match scr_node_draw_macro_vwait exactly
    var _header_h = 20;
    var _vly      = y + _header_h + 12;   // +12 to match the draw offset before the box renders
    var _val_x1   = _draw_x + 70;
    var _val_x2   = _draw_x + 160;
    var _val_h    = 18;
    var _var_w    = 28;
    var _var_x    = _val_x2 + 4;

    // ---- value box click ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _vly, _val_x2, _vly + _val_h)) {
        if (_use_var == 1) {
            // Open UV var picker for slot 3
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 3;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
        } else {
            with (obj_workspace_manager) {
                is_entering_text   = true;
                input_target_node  = other.id;
                input_target_index = 0;
                var _input_str;
                if (global.use_hex_display) {
                    var _h = decimal_to_hex(other.instructions[0][1]);
                    while (string_length(_h) < 2) _h = "0" + _h;
                    _input_str = "$" + string_upper(_h);
                } else {
                    _input_str = string(other.instructions[0][1]);
                }
                current_input_string = _input_str;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }

    // ---- VAR toggle click ----
    if (point_in_rectangle(mouse_x, mouse_y, _var_x, _vly, _var_x + _var_w, _vly + _val_h)) {
        scr_undo_snapshot();
        instructions[0][2] = (_use_var == 0) ? 1 : 0;
        if (instructions[0][2] == 0) instructions[0][3] = "";
        global.addresses_dirty = true;
        exit;
    }
}