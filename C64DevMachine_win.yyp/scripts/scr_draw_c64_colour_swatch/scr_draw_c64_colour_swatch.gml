function scr_draw_c64_colour_swatch(_x, _y, _col_index, _w, _h) {
    var _idx = clamp(is_real(_col_index) ? real(_col_index) : 0, 0, 15);
    // Rounded tile, no border (see scr_editor_colour_tile)
    scr_editor_colour_tile(_x, _y, _x + _w + 1, _y + _h + 1, scr_c64_pepto_colour(_idx));
}