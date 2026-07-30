/// @desc scr_node_step_macro_seek(_draw_x)
/// Handles LMB input for MACRO_SEEK nodes.
function scr_node_step_macro_seek(_draw_x) {
    // ensure instruction array is long enough
    while (array_length(instructions[0]) < 19) {
        array_push(instructions[0], 0);
    }
    if (!is_string(instructions[0][11])) instructions[0][11] = "";
    if (!is_string(instructions[0][13])) instructions[0][13] = "";
    if (!is_string(instructions[0][15])) instructions[0][15] = "";
    if (!is_string(instructions[0][17])) instructions[0][17] = "";

    var _ndist   = real(instructions[0][5]);
    var _mode    = real(instructions[0][9]);
    var _tx_uv   = real(instructions[0][10]);
    var _ty_uv   = real(instructions[0][12]);
    var _dist_uv = real(instructions[0][14]);
    var _ang_uv  = real(instructions[0][16]);
    var _tspr    = real(instructions[0][18]);

    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _row1    = y + 44;

    // ---- shared row geometry (must match scr_node_draw_macro_seek) ----
    var _but_width_n = 56;
    var _val_x1  = _draw_x + 60;
    var _val_x2  = _val_x1 + _but_width_n;
    var _tog_x   = _val_x2 + 6;
    var _tog_w   = 30;
    var _var_w   = 28;
    var _var_x   = _tog_x + _tog_w + 4;

    var _row2    = y + 70;   // TGT X
    var _row3    = y + 92;   // TGT Y
    var _row4    = y + 114;  // SPEED + MODE
    var _row5    = y + 136;  // NEAR + SPD-NEAR
    var _row6    = y + 158;  // DIST out
    var _row7    = y + 180;  // ANGLE out
    var _row8    = y + 202;  // 9th bit + bound

    var _out_bx1 = _draw_x + 50;
    var _out_bx2 = _out_bx1 + _but_width_n + 30;

    // ---- sprite toggle buttons ----
    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h)) {
            scr_undo_snapshot();
            instructions[0][1] = real(instructions[0][1]) ^ _bit_values[_si];
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- TGT X value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row2, _val_x2, _row2 + 18)) {
        if (_tx_uv == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 11;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 2;
                current_input_string = string(other.instructions[0][2]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }

    // ---- TGT X VAR toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _var_x, _row2, _var_x + _var_w, _row2 + 16)) {
        scr_undo_snapshot();
        if (_tx_uv == 0) {
            instructions[0][10] = 1;
        } else {
            instructions[0][10] = 0;
            instructions[0][11] = "";
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- TGT Y value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row3, _val_x2, _row3 + 18)) {
        if (_ty_uv == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 13;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 3;
                current_input_string = string(other.instructions[0][3]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }

    // ---- TGT Y VAR toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _var_x, _row3, _var_x + _var_w, _row3 + 16)) {
        scr_undo_snapshot();
        if (_ty_uv == 0) {
            instructions[0][12] = 1;
        } else {
            instructions[0][12] = 0;
            instructions[0][13] = "";
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- SPEED value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row4, _val_x2, _row4 + 18)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 4;
            current_input_string = string(other.instructions[0][4]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // ---- MODE cycle (4-DIR / 8-DIR) ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _row4, _tog_x + _tog_w + _var_w + 4, _row4 + 16)) {
        scr_undo_snapshot();
        if (_mode == 0) {
            instructions[0][9] = 1;
        } else {
            instructions[0][9] = 0;
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- NEAR DIST value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row5, _val_x2, _row5 + 18)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 5;
            current_input_string = string(other.instructions[0][5]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // ---- SPD-NEAR value box (only if near enabled) ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _row5, _tog_x + _tog_w + _var_w + 4, _row5 + 18)) {
        if (_ndist != 0) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 6;
                current_input_string = string(other.instructions[0][6]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }

    // ---- DIST OUT box (toggle var on/off, then pick) ----
    if (point_in_rectangle(mouse_x, mouse_y, _out_bx1, _row6, _out_bx2, _row6 + 18)) {
        if (_dist_uv == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 15;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
        } else {
            scr_undo_snapshot();
            instructions[0][14] = 1;
            global.addresses_dirty = true;
        }
        exit;
    }

    // ---- ANGLE OUT box (toggle var on/off, then pick) ----
    if (point_in_rectangle(mouse_x, mouse_y, _out_bx1, _row7, _out_bx2, _row7 + 18)) {
        if (_ang_uv == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 17;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
        } else {
            scr_undo_snapshot();
            instructions[0][16] = 1;
            global.addresses_dirty = true;
        }
        exit;
    }

    // ---- 9th-bit checkbox ----
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 6, _row8, _draw_x + 80, _row8 + 14)) {
        scr_undo_snapshot();
        if (real(instructions[0][7]) == 1) {
            instructions[0][7] = 0;
        } else {
            instructions[0][7] = 1;
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- TGT SPRITE cycle (OFF, 0..7) ----
    var _tspr_x = _draw_x + 144;
    if (point_in_rectangle(mouse_x, mouse_y, _tspr_x, _row6, _tspr_x + 44, _row6 + 40)) {
        scr_undo_snapshot();
        if (_tspr >= 8) {
            instructions[0][18] = 0;
        } else {
            instructions[0][18] = _tspr + 1;
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- WRAP/BOUNDED toggle ----
    var _bnd_x = _draw_x + 90;
    if (point_in_rectangle(mouse_x, mouse_y, _bnd_x, _row8, _bnd_x + 70, _row8 + 16)) {
        scr_undo_snapshot();
        if (real(instructions[0][8]) == 1) {
            instructions[0][8] = 0;
        } else {
            instructions[0][8] = 1;
        }
        global.addresses_dirty = true;
        exit;
    }

    exit;
}