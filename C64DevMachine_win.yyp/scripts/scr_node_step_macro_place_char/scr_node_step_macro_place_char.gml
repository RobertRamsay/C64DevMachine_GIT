/// @desc scr_node_step_macro_place_char(_draw_x)
/// Click handling for MACRO_PLACE_CHAR. Row anchors mirror the draw script.

function scr_node_step_macro_place_char(_draw_x) {

    // Backfill old saves to full slot count
    while (array_length(instructions[0]) <= 19) {
        var _n = array_length(instructions[0]);
        if (_n == 3 || _n == 6 || _n == 9 || _n == 10 || _n == 13 || _n == 19) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;

    var _chr_src   = is_real(instructions[0][7])  ? real(instructions[0][7])  : 0;
    var _vbtn_w    = 28;

    // ── Row 1: COL — VAR toggle (right) / picker or text entry (left) ──
    var _cvx = _draw_x + width - 38;
    if (point_in_rectangle(mouse_x, mouse_y, _cvx, _ly + 1, _cvx + _vbtn_w, _ly + 13)) {
        var _cv = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
        instructions[0][2] = (_cv == 0) ? 1 : 0;
        if (instructions[0][2] == 0) instructions[0][3] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _cvx - 2, _ly + 13)) {
        if (real(instructions[0][2]) == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 3;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 1;
                current_input_string = string(real(other.instructions[0][1]));
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ── Row 2: ROW ──
    var _rvx = _draw_x + width - 38;
    if (point_in_rectangle(mouse_x, mouse_y, _rvx, _ly + 1, _rvx + _vbtn_w, _ly + 13)) {
        var _rv = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0;
        instructions[0][5] = (_rv == 0) ? 1 : 0;
        if (instructions[0][5] == 0) instructions[0][6] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _rvx - 2, _ly + 13)) {
        if (real(instructions[0][5]) == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 6;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 4;
                current_input_string = string(real(other.instructions[0][4]));
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ── Row 3: SRC cycle 0 -> 1 -> 2 -> 0 ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 52, _ly, _draw_x + width - 10, _ly + 13)) {
        var _s = is_real(instructions[0][7]) ? real(instructions[0][7]) : 0;
        instructions[0][7] = (_s + 1) mod 3;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 4: char literal entry / var picker / asset picker ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 10, _ly + 13)) {
        if (_chr_src == 0) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 8;
                current_input_string = string(real(other.instructions[0][8]));
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        } else if (_chr_src == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 9;
        } else {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "BYTE_ASSET";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 10;
        }
        exit;
    }
    _ly += _lh;

    // ── Row 5: asset index (BYTE_DATA mode only) ──
    if (_chr_src == 2) {
        var _ivx = _draw_x + width - 38;
        if (point_in_rectangle(mouse_x, mouse_y, _ivx, _ly + 1, _ivx + _vbtn_w, _ly + 13)) {
            var _iv = is_real(instructions[0][11]) ? real(instructions[0][11]) : 0;
            instructions[0][11] = (_iv == 0) ? 1 : 0;
            if (instructions[0][11] == 0) instructions[0][13] = "";
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _ivx - 2, _ly + 13)) {
            if (real(instructions[0][11]) == 1) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_mode       = "VAR";
                label_picker_tab        = "UV";
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_target     = id;
                label_picker_index      = 13;
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
    _ly += _lh;

    // ── Row 6: SET COL checkbox + colour swatch ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + 90, _ly + 13)) {
        var _sc = is_real(instructions[0][14]) ? real(instructions[0][14]) : 0;
        instructions[0][14] = (_sc == 0) ? 1 : 0;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    var _colour_bx = _draw_x + width - 38;
    if (real(instructions[0][14]) == 1 &&
        point_in_rectangle(mouse_x, mouse_y, _colour_bx, _ly + 1, _colour_bx + _vbtn_w, _ly + 13)) {
        instructions[0][18] = (real(instructions[0][18]) == 0) ? 1 : 0;
        global.addresses_dirty = true;
        global.undo_dirty = true;
        exit;
    }
    _ly += _lh;

    // Row 7: retain both values when switching between LIT and VAR.
    if (real(instructions[0][14]) == 1 &&
        point_in_rectangle(mouse_x, mouse_y, _draw_x + 48, _ly, _draw_x + width - 10, _ly + 13)) {
        if (real(instructions[0][18]) == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 19;
        } else {
            instance_destroy(obj_ui_color_picker);
            var _picker_w = 256;
            var _spawn_x = (_draw_x + 62) - (_picker_w / 2);
            var _picker = instance_create_depth(_spawn_x, _ly + _lh, -9999, obj_ui_color_picker);
            _picker.target_node = id;
            _picker.target_row = 0;
            _picker.target_col = 15;
            mouse_clear(mb_left);
        }
        exit;
    }
    _ly += _lh;

    // ── Row 8: SCR BASE / ZP hex entry ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 48, _ly, _draw_x + 112, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 16;
            var _raw = real(other.instructions[0][16]);
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 4) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 142, _ly, _draw_x + width - 6, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 17;
            var _raw = real(other.instructions[0][17]);
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 2) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}