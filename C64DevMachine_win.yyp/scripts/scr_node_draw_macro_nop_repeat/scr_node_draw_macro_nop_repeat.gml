/// @desc scr_node_draw_macro_nop_repeat(_draw_x, _y)
/// Draws the NOP REPEAT node body: a decimal count box plus a live
/// bytes/cycles readout. Count is literal only — the NOP run is
/// unrolled at compile time, so the value must be known at assembly.
function scr_node_draw_macro_nop_repeat(_draw_x, _y) {
    var _header_h = 20;

    while (array_length(instructions[0]) < 2) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][1])) {
        instructions[0][1] = 0;
    }

    var _count = real(instructions[0][1]);

    draw_set_font(fnt_c64_tiny);

    // ---- ROW 1: COUNT value box ----
    var _row_y  = _y + _header_h + 12;
    var _val_h  = 18;
    var _val_x1 = _draw_x + 70;
    var _val_x2 = _draw_x + 160;

    draw_set_color(make_color_rgb(150, 150, 160));
    draw_text(_draw_x + 8, _y + _header_h + 4, "NOP\nCOUNT:");

    var _hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row_y, _val_x2, _row_y + _val_h);
    if (_hov) {
        draw_set_color(make_color_rgb(52, 52, 60));
    } else {
        draw_set_color(make_color_rgb(34, 34, 40));
    }
    draw_rectangle(_val_x1, _row_y, _val_x2, _row_y + _val_h, false);
    draw_set_color(make_color_rgb(120, 120, 135));
    draw_rectangle(_val_x1, _row_y, _val_x2, _row_y + _val_h, true);

    draw_set_halign(fa_center);
    draw_set_color(make_color_rgb(200, 200, 215));
    draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row_y + 1, string(_count));
    draw_set_halign(fa_left);

    // ---- ROW 2: bytes / cycles readout ----
    var _info_y = _row_y + _val_h + 4;
    if (_count == 0) {
        draw_set_color(make_color_rgb(150, 110, 60));
        draw_text(_draw_x + 8, _info_y, "EMITS NOTHING");
    } else {
        draw_set_color(make_color_rgb(110, 160, 120));
        draw_text(_draw_x + 8, _info_y,
                  string(_count) + " BYTES / " + string(_count * 2) + " CYCLES");
    }
}
