/// @desc scr_node_step_macro_move(_draw_x)
/// Handles LMB input for MACRO_MOVE nodes.
function scr_node_step_macro_move(_draw_x) {
    // ensure instruction array is long enough
    while (array_length(instructions[0]) < 11) {
        array_push(instructions[0], 0);
    }
    if (!is_string(instructions[0][8]))  instructions[0][8]  = "";
    if (!is_string(instructions[0][10])) instructions[0][10] = "";

    var _dx_mod = real(instructions[0][5]);
    var _dy_mod = real(instructions[0][6]);
    var _dx_uv  = real(instructions[0][7]);
    var _dy_uv  = real(instructions[0][9]);

    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _row1    = y + 44;
    var _val_x1  = _draw_x + 38;
    var _val_x2  = _draw_x + 120;
    var _tog_x   = _val_x2 + 4;
    var _tog_w   = 34;
    var _tog_h   = 16;
    var _var_w   = 28;
    var _var_x   = _tog_x + _tog_w + 4;
    var _row2    = y + 70;
    var _row3    = y + 92;
    var _row4    = y + 114;

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

    // ---- DX value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row2, _val_x2, _row2 + 18)) {
        if (_dx_uv == 1) {
            // Open UV var picker for slot 8
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 8;
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

    // ---- DX WRAP/STOP toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _row2, _tog_x + _tog_w, _row2 + _tog_h)) {
        scr_undo_snapshot();
        instructions[0][5] = (_dx_mod == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }

    // ---- DX VAR toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _var_x, _row2, _var_x + _var_w, _row2 + _tog_h)) {
        scr_undo_snapshot();
        instructions[0][7] = (_dx_uv == 0) ? 1 : 0;
        if (instructions[0][7] == 0) instructions[0][8] = ""; // clear var name when leaving VAR mode
        global.addresses_dirty = true;
        exit;
    }

    // ---- DY value box ----
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row3, _val_x2, _row3 + 18)) {
        if (_dy_uv == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 10;
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

    // ---- DY WRAP/STOP toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _row3, _tog_x + _tog_w, _row3 + _tog_h)) {
        scr_undo_snapshot();
        instructions[0][6] = (_dy_mod == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }

    // ---- DY VAR toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _var_x, _row3, _var_x + _var_w, _row3 + _tog_h)) {
        scr_undo_snapshot();
        instructions[0][9] = (_dy_uv == 0) ? 1 : 0;
        if (instructions[0][9] == 0) instructions[0][10] = ""; // clear var name when leaving VAR mode
        global.addresses_dirty = true;
        exit;
    }

    // ---- Wide-X checkbox ----
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 6, _row4, _draw_x + 160, _row4 + 14)) {
        scr_undo_snapshot();
        instructions[0][4] = (real(instructions[0][4]) == 1) ? 0 : 1;
        global.addresses_dirty = true;
        exit;
    }

    exit;
}