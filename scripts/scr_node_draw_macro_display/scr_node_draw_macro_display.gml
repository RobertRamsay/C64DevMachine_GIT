function scr_node_draw_macro_display(_draw_x, _y) {
    var _header_h = 20;
    while (array_length(instructions[0]) < 2) {
        array_push(instructions[0], 1);
    }
    var _mode = 0;
    if (is_real(instructions[0][1])) {
        _mode = real(instructions[0][1]);
    }

    var _row_y = _y + _header_h + 12;

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(200, 160, 60));
    draw_text(_draw_x + 8, _row_y + 3, "SCREEN:");

    // ---- ON / OFF toggle pair ----
    var _btn_w = 44;
    var _btn_h = 18;
    var _on_x  = _draw_x + 74;
    var _off_x = _on_x + _btn_w + 6;

    var _on_hov  = point_in_rectangle(mouse_x, mouse_y, _on_x,  _row_y, _on_x  + _btn_w, _row_y + _btn_h);
    var _off_hov = point_in_rectangle(mouse_x, mouse_y, _off_x, _row_y, _off_x + _btn_w, _row_y + _btn_h);

    // ON
    if (_mode == 1) {
        draw_set_color(make_color_rgb(40, 140, 60));
    } else {
        draw_set_color(_on_hov ? make_color_rgb(40, 60, 40) : make_color_rgb(28, 32, 28));
    }
    draw_rectangle(_on_x, _row_y, _on_x + _btn_w, _row_y + _btn_h, false);
    draw_set_color((_mode == 1) ? c_lime : make_color_rgb(70, 80, 70));
    draw_rectangle(_on_x, _row_y, _on_x + _btn_w, _row_y + _btn_h, true);
    draw_set_halign(fa_center);
    draw_set_color((_mode == 1) ? c_white : make_color_rgb(110, 120, 110));
    draw_text(_on_x + _btn_w * 0.5, _row_y + 1, "ON");

    // OFF
    if (_mode == 0) {
        draw_set_color(make_color_rgb(140, 50, 40));
    } else {
        draw_set_color(_off_hov ? make_color_rgb(60, 40, 40) : make_color_rgb(32, 28, 28));
    }
    draw_rectangle(_off_x, _row_y, _off_x + _btn_w, _row_y + _btn_h, false);
    draw_set_color((_mode == 0) ? make_color_rgb(255, 120, 90) : make_color_rgb(80, 70, 70));
    draw_rectangle(_off_x, _row_y, _off_x + _btn_w, _row_y + _btn_h, true);
    draw_set_color((_mode == 0) ? c_white : make_color_rgb(120, 110, 110));
    draw_text(_off_x + _btn_w * 0.5, _row_y + 1, "OFF");
    draw_set_halign(fa_left);

    // ---- info line ----
    draw_set_color(make_color_rgb(90, 90, 110));
    var _info = "$D011 BIT 4 - RMW SAFE";
    draw_text(_draw_x + 8, _row_y + _btn_h + 5, _info);
}