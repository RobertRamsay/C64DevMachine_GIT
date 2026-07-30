function scr_node_step_macro_priority(_draw_x) {

    var _btn_w = 22, _btn_h = 18, _btn_gap = 2;
    var _btn_sx = _draw_x + 6;
    var _row1   = y + 44;
    var _row2   = y + 64;
    var _tog_w  = 80;
    var _tog_h  = 14;
    var _tog_x  = _draw_x + 6;

    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];

    // ---- sprite toggle buttons ----
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h)) {
            instructions[0][1] = real(instructions[0][1]) ^ _bit_values[_si];
            global.addresses_dirty = true;
            exit;
        }
    }

    // ensure instruction array is long enough
    while (array_length(instructions[0]) < 3) {
        array_push(instructions[0], 0);
    }

    // ---- FRONT/BEHIND toggle ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _row2, _tog_x + _tog_w, _row2 + _tog_h)) {
        instructions[0][2] = (real(instructions[0][2]) == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }

    exit;
}