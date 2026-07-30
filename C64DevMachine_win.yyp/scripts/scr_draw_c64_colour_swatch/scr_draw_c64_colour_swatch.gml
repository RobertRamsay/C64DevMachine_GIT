function scr_draw_c64_colour_swatch(_x, _y, _col_index, _w, _h) {
    var _idx = clamp(is_real(_col_index) ? real(_col_index) : 0, 0, 15);
    draw_set_color(scr_c64_pepto_colour(_idx));
    draw_rectangle(_x, _y, _x + _w, _y + _h, false);
    draw_set_color(c_gray);
    draw_rectangle(_x, _y, _x + _w, _y + _h, true);
}