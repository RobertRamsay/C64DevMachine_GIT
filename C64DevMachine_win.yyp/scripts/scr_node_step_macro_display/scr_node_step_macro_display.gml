function scr_node_step_macro_display(_draw_x) {
    while (array_length(instructions[0]) < 2) {
        array_push(instructions[0], 1);
    }
    var _mode = 0;
    if (is_real(instructions[0][1])) {
        _mode = real(instructions[0][1]);
    }

    // Geometry — must match scr_node_draw_macro_display exactly
    var _header_h = 20;
    var _row_y    = y + _header_h + 12;
    var _btn_w    = 44;
    var _btn_h    = 18;
    var _on_x     = _draw_x + 74;
    var _off_x    = _on_x + _btn_w + 6;

    if (point_in_rectangle(mouse_x, mouse_y, _on_x, _row_y, _on_x + _btn_w, _row_y + _btn_h)) {
        if (_mode != 1) {
            scr_undo_snapshot();
            instructions[0][1]     = 1;
            global.addresses_dirty = true;
        }
        exit;
    }

    if (point_in_rectangle(mouse_x, mouse_y, _off_x, _row_y, _off_x + _btn_w, _row_y + _btn_h)) {
        if (_mode != 0) {
            scr_undo_snapshot();
            instructions[0][1]     = 0;
            global.addresses_dirty = true;
        }
        exit;
    }
}