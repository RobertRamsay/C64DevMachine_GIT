function scr_node_draw_macro_wait(_draw_x, _y) {
    var _header_h = 20;
    while (array_length(instructions[0]) < 4) {
        var _wn = array_length(instructions[0]);
        if (_wn == 3) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }
    if (!is_string(instructions[0][3])) instructions[0][3] = "";

    var _frames = 50;
    if (is_real(instructions[0][1])) {
        _frames = real(instructions[0][1]);
    }
    var _use_var = 0;
    if (is_real(instructions[0][2])) {
        _use_var = real(instructions[0][2]);
    }
    var _vname = string(instructions[0][3]);

    draw_set_font(fnt_c64_tiny);

    // ---- ROW 1: FRAMES value + VAR toggle ----
    var _row_y  = _y + _header_h + 12;
    var _val_h  = 18;
    var _val_x1 = _draw_x + 70;
    var _val_x2 = _draw_x + 160;

    draw_set_color(make_color_rgb(60, 200, 220));
    draw_text(_draw_x + 8, _y + _header_h + 4, "WAIT\nFRAMES:");

    var _hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row_y, _val_x2, _row_y + _val_h);
    if (_use_var == 1) {
        draw_set_color(_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_hov ? make_color_rgb(30, 60, 70) : make_color_rgb(20, 40, 48));
    }
    draw_rectangle(_val_x1, _row_y, _val_x2, _row_y + _val_h, false);
    draw_set_color((_use_var == 1) ? make_color_rgb(160, 130, 40) : make_color_rgb(50, 130, 150));
    draw_rectangle(_val_x1, _row_y, _val_x2, _row_y + _val_h, true);

    draw_set_halign(fa_center);
    if (_use_var == 1) {
        draw_set_color(c_yellow);
        var _vshow = "<PICK>";
        if (_vname != "") {
            _vshow = _vname;
        }
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row_y + 1, _vshow);
    } else {
        draw_set_color(make_color_rgb(100, 220, 240));
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row_y + 1, string(_frames));
    }
    draw_set_halign(fa_left);

    // VAR toggle
    var _var_w = 28;
    var _var_x = _val_x2 + 4;
    draw_set_color((_use_var == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
    draw_rectangle(_var_x, _row_y, _var_x + _var_w, _row_y + _val_h, false);
    draw_set_color((_use_var == 1) ? c_yellow : make_color_rgb(140, 140, 160));
    draw_set_halign(fa_center);
    draw_text(_var_x + _var_w * 0.5, _row_y + 1, "VAR");
    draw_set_halign(fa_left);

    // ---- ROW 2: real-time readout ----
    var _t_y = _row_y + _val_h + 5;
    if (_use_var == 1) {
        draw_set_color(make_color_rgb(160, 140, 60));
        draw_text(_draw_x + 8, _t_y, "RUNTIME VALUE - BYTE, MAX 255");
    } else {
        var _pal_ms  = round((_frames / 50.0) * 1000);
        var _ntsc_ms = round((_frames / 60.0) * 1000);
        draw_set_color(make_color_rgb(60, 200, 220));
        draw_text(_draw_x + 8, _t_y, "PAL: " + string(_pal_ms) + "MS   NTSC: " + string(_ntsc_ms) + "MS");
    }

    // ---- ROW 3: clobber note ----
    var _c_y = _t_y + 11;
    draw_set_color(make_color_rgb(90, 90, 110));
    draw_text(_draw_x + 8, _c_y, "COUNTS IN X - CLOBBERS A + X");
}