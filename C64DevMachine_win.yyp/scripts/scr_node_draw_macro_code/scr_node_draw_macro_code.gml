/// @function scr_node_draw_macro_code(_draw_x, _y)
function scr_node_draw_macro_code(_draw_x, _y) {
    var _code_text = string(instructions[0][1]);
    var _desc      = code_descriptor;
    var _px        = _draw_x + 8;
    var _ly        = _y + 24 + 4;

    // Descriptor
    draw_set_font(fnt_c64_code);
    draw_set_color(make_color_rgb(140, 180, 140));
    draw_text(_px, _ly, _desc);
    _ly += 18;

    // EDIT button
    var _btn_x1 = _draw_x + 10;
    var _btn_y1 = _ly + 4;
    var _btn_x2 = _draw_x + width - 8;
    var _btn_y2 = _btn_y1 + 16;
    var _hover  = point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2);
    draw_set_color(_hover ? make_color_rgb(60, 110, 200) : make_color_rgb(20, 60, 110));
    draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, false);
    draw_set_color(c_white);
    draw_set_font(fnt_C64_Angled);
    draw_set_halign(fa_center);
    draw_text((_btn_x1 + _btn_x2) / 2, _btn_y1 + 1 , "EDIT ASM CODE");
    draw_set_halign(fa_left);
    _ly = _btn_y2 + 6;

	// Byte/cycle stats — cached, only recomputed when text changes
if (code_cache_dirty) {
        code_cached_lines = (_code_text != "") ? array_length(string_split(_code_text, "\n")) : 0;
        code_seg_cache    = [];
        global.addresses_dirty = true;
        code_cache_dirty  = false;
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_aqua);
    draw_text(_px, _ly, string(total_node_size) + " BYTES");
    draw_set_color(c_orange);
    draw_text(_px + 70, _ly, string(node_cycles) + " CYC");
    if (code_cached_lines > 0) {
        draw_set_color(make_color_rgb(80, 120, 200));
        draw_text(_px + 125, _ly, string(code_cached_lines) + " LINES");
    }
}
