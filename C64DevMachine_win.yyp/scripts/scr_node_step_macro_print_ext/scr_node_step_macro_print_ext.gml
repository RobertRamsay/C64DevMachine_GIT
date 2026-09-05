/// @desc scr_node_step_macro_print_ext(_draw_x)
/// Handles clicks for MACRO_PRINT_EXT node fields.
/// instructions[0]: ["macro_print_ext", sx, sy, col, clr, src_mode,
///                    var_name, reg_id, fmt, align_h, align_v, pad]

function scr_node_step_macro_print_ext(_draw_x) {
    if (scr_print_dynamic_step(_draw_x, y + height - 56, 12, 9, 10)) exit;


    var _row_h = 18;
    var _ry    = y + 28;

    // ── Row 1: X / Y / COL text fields ──
    // X field — editing X clears H-align override (slot 9 -> DEF), matching MACRO_PRINT
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 28, _ry, _draw_x + 66, _ry + 14)) {
        while (array_length(instructions[0]) <= 9) {
            array_push(instructions[0], 0);
        }
        instructions[0][9] = 0;
        global.addresses_dirty = true;
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            if (array_length(other.instructions[0]) > 12) other.instructions[0][12] = 0;
            current_input_string = string(other.instructions[0][1]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    // Y field — editing Y clears V-align override (slot 10 -> DEF), matching MACRO_PRINT
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 88, _ry, _draw_x + 126, _ry + 14)) {
        while (array_length(instructions[0]) <= 10) {
            array_push(instructions[0], 0);
        }
        instructions[0][10] = 0;
        global.addresses_dirty = true;
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            if (array_length(other.instructions[0]) > 14) other.instructions[0][14] = 0;
            current_input_string = string(other.instructions[0][2]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
	
    // COL field
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 162, _ry, _draw_x + 200, _ry + 14)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 3;
            if (array_length(other.instructions[0]) > 16) other.instructions[0][16] = 0;
            current_input_string = string(other.instructions[0][3]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _ry += _row_h;

    // ── Row 2: SOURCE toggle ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 50, _ry, _draw_x + width - 10, _ry + 14)) {
        var _cur = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;
        instructions[0][5] = (_cur == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }
    _ry += _row_h;

    // ── Row 3: VAR picker (VAR mode) or REGISTER cycle (REG mode) ──
    var _src_mode = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;
    if (_src_mode == 0) {
        // open VAR picker — writes to instructions[0][6]
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 50, _ry, _draw_x + width - 10, _ry + 14)) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_index      = 6;
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_mode       = "VAR";
            label_picker_target     = id;
            exit;
        }
    } else {
        // cycle register 0..4
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 50, _ry, _draw_x + width - 10, _ry + 14)) {
            var _r = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 0;
            _r = (_r + 1) mod 5;
            instructions[0][7] = _r;
            global.addresses_dirty = true;
            exit;
        }
    }
    _ry += _row_h;

    // ── Row 4: FORMAT cycle 0..3 ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 50, _ry, _draw_x + width - 10, _ry + 14)) {
        var _f = (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) ? real(instructions[0][8]) : 0;
        _f = (_f + 1) mod 4;
        instructions[0][8] = _f;
        global.addresses_dirty = true;
        exit;
    }
    _ry += _row_h;

    // ── Row 4b: H-ALIGN buttons (writes slot 9) ──
    var _pe_btn_w = 34;
    for (var _ai = 0; _ai < 4; _ai++) {
        var _bx = _draw_x + 30 + (_ai * (_pe_btn_w + 2));
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _ry, _bx + _pe_btn_w, _ry + 14)) {
            while (array_length(instructions[0]) <= 9) {
                array_push(instructions[0], 0);
            }
            instructions[0][9] = _ai;
            global.addresses_dirty = true;
            exit;
        }
    }
    _ry += _row_h;

    // ── Row 4c: V-ALIGN buttons (writes slot 10) ──
    for (var _ai = 0; _ai < 4; _ai++) {
        var _bx = _draw_x + 30 + (_ai * (_pe_btn_w + 2));
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _ry, _bx + _pe_btn_w, _ry + 14)) {
            while (array_length(instructions[0]) <= 10) {
                array_push(instructions[0], 0);
            }
            instructions[0][10] = _ai;
            global.addresses_dirty = true;
            exit;
        }
    }
    _ry += _row_h;

    // ── Row 5: PAD toggle + CLEAR checkbox ──
    // PAD toggle — covers the "PAD:" label + value text (draw puts value at +42)
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 10, _ry, _draw_x + 95, _ry + 14)) {
        var _p = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
        instructions[0][11] = (_p == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }
    // PRE-CLEAR checkbox — draw uses _cbx = _draw_x + 112, box at (_cbx-8 .. _cbx+4),
    // label "PRE-CLEAR?" at _cbx+8. Hit zone spans box + label so either is clickable.
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 104, _ry + 2, _draw_x + width - 10, _ry + 14)) {
        var _c = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
        instructions[0][4] = (_c == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }
    _ry += _row_h;
}