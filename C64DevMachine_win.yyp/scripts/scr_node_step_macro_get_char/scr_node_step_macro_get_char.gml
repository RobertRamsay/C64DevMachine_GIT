/// @desc scr_node_step_macro_get_char(_draw_x)
/// Click handling for MACRO_GET_CHAR. Row anchors mirror the draw script.

function scr_node_step_macro_get_char(_draw_x) {

    // Backfill old saves to full slot count
    while (array_length(instructions[0]) <= 11) {
        var _n = array_length(instructions[0]);
        if (_n == 3 || _n == 6 || _n == 7 || _n == 9) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;

    var _get_col = is_real(instructions[0][8]) ? real(instructions[0][8]) : 0;
    var _vbtn_w  = 28;

    // ── Row 1: COL ──
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

    // ── Row 3: DEST var picker ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 7;
        exit;
    }
    _ly += _lh;

    // ── Row 4: GET COL checkbox ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + width - 6, _ly + 13)) {
        var _gc = is_real(instructions[0][8]) ? real(instructions[0][8]) : 0;
        instructions[0][8] = (_gc == 0) ? 1 : 0;
        if (instructions[0][8] == 0) instructions[0][9] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 5: DEST colour var picker ──
    if (_get_col == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
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
            exit;
        }
    }
    _ly += _lh;

    // ── Row 6: SCR BASE / ZP hex entry ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 48, _ly, _draw_x + 112, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 10;
            var _raw = real(other.instructions[0][10]);
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
            input_target_index   = 11;
            var _raw = real(other.instructions[0][11]);
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 2) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}