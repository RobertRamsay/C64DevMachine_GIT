function scr_node_draw_macro_vwait(_draw_x, _y) {
    var _header_h = 20;
    var _line_h   = 12;

    // Ensure slots exist
    while (array_length(instructions[0]) < 4) {
        array_push(instructions[0], 0);
    }
    if (!is_string(instructions[0][3])) instructions[0][3] = "";

    var _vline  = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0xFB;
    var _use_var = real(instructions[0][2]);
    var _vname   = string(instructions[0][3]);

    draw_set_font(fnt_c64_tiny);
    var _vly = _y + _header_h ;
    draw_set_color(make_color_rgb(40,200,180));
    draw_text(_draw_x +8, _vly+6, "RASTER\nLINE:");

    // ---- value box ----
    var _val_x1 = _draw_x + 70;
    var _val_x2 = _draw_x + 160;
    var _val_h  = 18;

    var _hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _vly - 2, _val_x2, _vly - 2 + _val_h + 2);
    if (_use_var == 1) {
        draw_set_color(_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 45, 30));
    }
	_vly+=12
    draw_rectangle(_val_x1, _vly, _val_x2, _vly + _val_h, false);
    draw_set_color((_use_var == 1) ? make_color_rgb(160, 130, 40) : make_color_rgb(60, 100, 60));
    draw_rectangle(_val_x1, _vly, _val_x2, _vly + _val_h, true);

    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    if (_use_var == 1) {
        draw_set_color(c_yellow);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _vly + 1, (_vname != "") ? _vname : "<PICK>");
    } else {
        draw_set_color(make_color_rgb(100, 220, 100));
        var _display_str;
        if (global.use_hex_display) {
            var _vhex = string_upper(decimal_to_hex(_vline));
            while (string_length(_vhex) < 2) _vhex = "0" + _vhex;
            _display_str = "$" + _vhex;
        } else {
            _display_str = string(_vline);
        }
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _vly + 1, _display_str);
    }
    draw_set_halign(fa_left);

    // ---- VAR toggle ----
    var _var_w = 28;
    var _var_x = _val_x2 + 4;
    draw_set_color((_use_var == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
    draw_rectangle(_var_x, _vly , _var_x + _var_w, _vly  + _val_h, false);
    draw_set_color((_use_var == 1) ? c_yellow : make_color_rgb(140, 140, 160));
    draw_set_halign(fa_center);
    draw_text(_var_x + _var_w * 0.5, _vly + 1, "VAR");
    draw_set_halign(fa_left);
}