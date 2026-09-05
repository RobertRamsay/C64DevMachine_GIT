function scr_node_step_macro_print(_draw_x) {
    if (scr_print_dynamic_step(_draw_x, y + scr_print_controls_offset(id), 18, 7, 8)) exit;

    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;
    var _align_h  = (array_length(instructions[0]) > 7) ? real(instructions[0][7]) : 0;
    var _align_v  = (array_length(instructions[0]) > 8) ? real(instructions[0][8]) : 0;
    var _src_mode = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;

    // Row 1: X click
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 28, _fy, _draw_x + 60, _fy + 16)) {
        while (array_length(instructions[0]) < 8) array_push(instructions[0], 0);
        instructions[0][7] = 0;
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            if (array_length(other.instructions[0]) > 18) other.instructions[0][18] = 0;
            current_input_string = string(other.instructions[0][1]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // Row 1: Y click
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 85, _fy, _draw_x + 110, _fy + 16)) {
        while (array_length(instructions[0]) < 9) array_push(instructions[0], 0);
        instructions[0][8] = 0;
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            if (array_length(other.instructions[0]) > 20) other.instructions[0][20] = 0;
            current_input_string = string(other.instructions[0][2]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // Row 1: LOC click — only editable in inline mode
    if (_src_mode == 0 && point_in_rectangle(mouse_x, mouse_y, _draw_x + 144, _fy, _draw_x + width - 8, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 6;
            var _raw = (array_length(other.instructions[0]) > 6) ? real(other.instructions[0][6]) : 0x2000;
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 4) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _fy += _line_h;

    // Row 2: COL swatch
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 50, _fy, _draw_x + 110, _fy + 16)) {
        if (array_length(instructions[0]) > 22) instructions[0][22] = 0;
        instance_destroy(obj_ui_color_picker);
        var _picker_w     = 256;
        var _swatch_center = _draw_x + 60;
        var _spawn_x      = _swatch_center - (_picker_w / 2);
        var _py           = _fy + _line_h;
        var _picker       = instance_create_depth(_spawn_x, _py, -9999, obj_ui_color_picker);
        _picker.target_node = id;
        _picker.target_row  = 0;
        _picker.target_col  = 3;
        mouse_clear(mb_left);
        exit;
    }
    _fy += _line_h;

    // Row 2b: SCR BASE click
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 76, _fy, _draw_x + width - 8, _fy + 12)) {
        while (array_length(instructions[0]) <= 13) array_push(instructions[0], 0x0400);
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 13;
            var _raw = (array_length(other.instructions[0]) > 13) ? real(other.instructions[0][13]) : 0x0400;
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 4) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _fy += _line_h;

    // Row 3: CLR toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 10, _fy - 2, _draw_x + 100, _fy + 12)) {
        var _cur = (array_length(instructions[0]) > 4) ? real(instructions[0][4]) : 0;
        instructions[0][4] = (_cur == 1) ? 0 : 1;
        exit;
    }
    _fy += _line_h;

    // Row 4: H-ALIGN buttons
    var _btn_w = 34;
    for (var _i = 0; _i < 4; _i++) {
        var _bx = _draw_x + 28 + (_i * (_btn_w + 2));
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _fy, _bx + _btn_w, _fy + 14)) {
            while (array_length(instructions[0]) < 8) array_push(instructions[0], 0);
            instructions[0][7] = _i;
            global.addresses_dirty = true;
            exit;
        }
    }
    _fy += _line_h;

    // Row 5: V-ALIGN buttons
    for (var _i = 0; _i < 4; _i++) {
        var _bx = _draw_x + 28 + (_i * (_btn_w + 2));
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _fy, _bx + _btn_w, _fy + 14)) {
            while (array_length(instructions[0]) < 9) array_push(instructions[0], 0);
            instructions[0][8] = _i;
            global.addresses_dirty = true;
            exit;
        }
    }
    _fy += _line_h;
    _fy += _line_h / 2;

    // Row 6: SOURCE toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
        while (array_length(instructions[0]) <= 9) array_push(instructions[0], 0);
        var _cur = is_real(instructions[0][9]) ? real(instructions[0][9]) : 0;
        instructions[0][9] = (_cur == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }
    _fy += _line_h;

    if (_src_mode == 0) {
        // Row 7: inline text entry
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 5;
                var _txt = (array_length(other.instructions[0]) > 5) ? string(other.instructions[0][5]) : "";
                current_input_string = _txt;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
    } else {
        // Row 7: ASSET picker — pick from the TEXT_DATA list rather than
        // cycling blind through it.
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
            while (array_length(instructions[0]) <= 10) array_push(instructions[0], "");
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "TEXT_ASSET";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 10;
            exit;
        }
        _fy += _line_h;

        // Row 8: START offset — VAR toggle (right) / picker or text entry (left)
        while (array_length(instructions[0]) <= 17) {
            if (array_length(instructions[0]) == 15 || array_length(instructions[0]) == 17) {
                array_push(instructions[0], "");
            } else {
                array_push(instructions[0], 0);
            }
        }
        var _svb_x = _draw_x + width - 40;
        if (point_in_rectangle(mouse_x, mouse_y, _svb_x, _fy + 1, _svb_x + 28, _fy + 12)) {
            var _sc = is_real(instructions[0][14]) ? real(instructions[0][14]) : 0;
            instructions[0][14] = (_sc == 0) ? 1 : 0;
            if (instructions[0][14] == 0) instructions[0][15] = "";
            global.addresses_dirty = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _svb_x - 2, _fy + 12)) {
            if (real(instructions[0][14]) == 1) {
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
                label_picker_word_only  = true;  // START offset must be a WORD var
                label_picker_byte_only  = false;
                for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                    if (global.named_loc_meta[_ki].type == "UV") {
                        array_push(label_picker_list, global.named_loc_meta[_ki].name);
                    }
                }
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 11;
                    current_input_string = string(real(other.instructions[0][11]));
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
        _fy += _line_h;

        // Row 9: END offset — VAR toggle (right) / picker or text entry (left)
        var _evb_x = _draw_x + width - 40;
        if (point_in_rectangle(mouse_x, mouse_y, _evb_x, _fy + 1, _evb_x + 28, _fy + 12)) {
            var _ec = is_real(instructions[0][16]) ? real(instructions[0][16]) : 0;
            instructions[0][16] = (_ec == 0) ? 1 : 0;
            if (instructions[0][16] == 0) instructions[0][17] = "";
            global.addresses_dirty = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _evb_x - 2, _fy + 12)) {
            if (real(instructions[0][16]) == 1) {
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
                label_picker_word_only  = true;  // END offset must be a WORD var
                label_picker_byte_only  = false;
                for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                    if (global.named_loc_meta[_ki].type == "UV") {
                        array_push(label_picker_list, global.named_loc_meta[_ki].name);
                    }
                }
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 12;
                    current_input_string = string(real(other.instructions[0][12]));
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
    }
}