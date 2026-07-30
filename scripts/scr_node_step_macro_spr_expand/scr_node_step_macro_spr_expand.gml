function scr_node_step_macro_spr_expand(_draw_x) {
    show_debug_message("EXPAND step: my=" + string(mouse_y) + " rel_to_y=" + string(mouse_y - y));
    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _row1    = y + 44;
    var _row2    = y + 76;
    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];
    // (array padding moved inside Y-row hit branch)

    // ---- X EXPAND row (row1) ----
    var _x_val = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h)) {
            instructions[0][1] = real(_x_val ^ _bit_values[_si]);
            global.addresses_dirty = true;
            exit;
        }
    }
    // ---- Y EXPAND row (row2) ----
    var _y_val = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _row2, _bx + _btn_w, _row2 + _btn_h)) {
            while (array_length(instructions[0]) < 3) array_push(instructions[0], 0);
            instructions[0][2] = real(_y_val ^ _bit_values[_si]);
            global.addresses_dirty = true;
            exit;
        }
    }
    // ---- CLEAR button ----
    var _clr_w = 44;
    var _clr_h = 14;
    var _clr_x = _btn_sx + 8 * (_btn_w + _btn_gap) - _btn_gap - _clr_w;
    var _clr_y = y + 102;
    if (point_in_rectangle(mouse_x, mouse_y, _clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h)) {
        instructions[0][1] = 0;
        instructions[0][2] = 0;
        global.addresses_dirty = true;
        exit;
    }
    exit;
}