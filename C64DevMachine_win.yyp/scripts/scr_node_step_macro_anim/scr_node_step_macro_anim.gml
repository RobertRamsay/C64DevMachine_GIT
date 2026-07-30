function scr_node_step_macro_anim(_draw_x) {
    while (array_length(instructions[0]) < 11) array_push(instructions[0], "");
    var _val_x1 = _draw_x + 54;
    var _val_x2 = _draw_x + width - 8;
    var _fld_h  = 16;
    while (array_length(instructions[0]) < 36) array_push(instructions[0], "");
    var _box_w   = 61;
    var _box_gap = 4;
    var _bx0 = _draw_x + 4;
    var _bx1 = _bx0 + _box_w + _box_gap;
    var _bx2 = _bx1 + _box_w + _box_gap;
    var _bx3_9b = _bx2 + _box_w + _box_gap; // 9th-bit checkbox column
    var _cb_size = 10;
    // ---- Per-slot frame / X / Y fields + 9bit toggle ----
    var _slot_start_y = y + 50;
    var _slot_gap_y = 30;
    for (var _si = 0; _si < 8; _si++) {
        var _ry  = _slot_start_y + _si * _slot_gap_y;
        var _ry2 = _ry + 12;

        // FRAMES box
        if (point_in_rectangle(mouse_x, mouse_y, _bx0, _ry2, _bx0 + _box_w, _ry2 + _fld_h)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 2 + _si;
                current_input_string = string(other.instructions[0][2 + _si]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
        // X box
        if (point_in_rectangle(mouse_x, mouse_y, _bx1, _ry2, _bx1 + _box_w, _ry2 + _fld_h)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 11 + _si;
                current_input_string = string(other.instructions[0][11 + _si]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
        // Y box
        if (point_in_rectangle(mouse_x, mouse_y, _bx2, _ry2, _bx2 + _box_w, _ry2 + _fld_h)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 19 + _si;
                current_input_string = string(other.instructions[0][19 + _si]);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
        // 9th-bit checkbox per slot — toggles instructions[0][27 + _si]
        var _9b_cx = _bx3_9b;
        var _9b_cy = _ry2 + 3;
        var _9b_sz = 10;
        if (point_in_rectangle(mouse_x, mouse_y, _9b_cx, _9b_cy, _9b_cx + _9b_sz, _9b_cy + _9b_sz)) {
            scr_undo_snapshot();
            var _cur_9b = (string(instructions[0][27 + _si]) == "1");
            if (_cur_9b) {
                instructions[0][27 + _si] = "0";
            } else {
                instructions[0][27 + _si] = "1";
            }
            global.addresses_dirty = true;
            exit;
        }
    }

    var _spd_y    = _slot_start_y + 8 * _slot_gap_y + 4;
    var _delay_x2 = _draw_x + 80;
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _spd_y, _delay_x2, _spd_y + _fld_h)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            current_input_string = string(other.instructions[0][1]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    // ---- Loop toggle ----
    var _cb_x = _delay_x2 + 48;
    if (point_in_rectangle(mouse_x, mouse_y, _cb_x, _spd_y + 2, _cb_x + _cb_size, _spd_y + 2 + _cb_size)) {
        var _cur = (string(instructions[0][10]) == "1");
        if (_cur) {
            instructions[0][10] = "0";
        } else {
            instructions[0][10] = "1";
        }
        global.addresses_dirty = true;
        exit;
    }

    // ---- DONE VAR picker (one-shot only) ----
    var _loop_now = (string(instructions[0][10]) == "1");
    if (!_loop_now) {
        var _footer_y = _spd_y + 20;
        var _reset_y  = _footer_y + 14;
        var _dv_y     = _reset_y + 14;
        var _dv_x2    = _draw_x + width - 8;
        if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _dv_y, _dv_x2, _dv_y + _fld_h)) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_index      = 0;
            label_picker_scroll     = 0;
			label_picker_mode       = "VAR";
            label_picker_target     = id;
            label_picker_index      = 35; // DONE VAR slot — VAR picker writes instructions[0][35]
            exit;
        }
    }
    exit;
}