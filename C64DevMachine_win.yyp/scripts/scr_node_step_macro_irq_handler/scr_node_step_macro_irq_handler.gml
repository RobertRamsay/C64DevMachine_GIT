function scr_node_step_macro_irq_handler(_draw_x) {
    var _mode = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
    var _px   = _draw_x + 8;
    var _ly   = y + 22;
    var _lh   = 14;

    // ROW 0 — VECTOR MODE toggle click
    if (point_in_rectangle(mouse_x, mouse_y, _px + 80, _ly, _draw_x + width - 8, _ly + _lh)) {
        while (array_length(instructions[0]) < 2) array_push(instructions[0], 0);
        instructions[0][1] = (_mode == 0) ? 1 : 0;
        global.addresses_dirty = true;
        exit;
    }
}