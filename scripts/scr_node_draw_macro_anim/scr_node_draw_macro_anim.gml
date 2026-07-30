function scr_node_draw_macro_anim(_draw_x) {

    while (array_length(instructions[0]) < 11) array_push(instructions[0], "");

    var _speed = (is_real(instructions[0][1])) ? real(instructions[0][1]) : 8;

    // ---- SLOTS label ----
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 28, "SLOT OFFSETS      (INIT-JSR CALLED)");

    // ---- Per-slot asset rows ----
    var _lbl_x  = _draw_x + 6;
    var _val_x1 = _draw_x + 54;
    var _val_x2 = _draw_x + width - 8;
    var _fld_h  = 16;
    var _btn_col = make_color_rgb(30, 80, 120);
    draw_set_font(fnt_c64_tiny);

    while (array_length(instructions[0]) < 36) array_push(instructions[0], "");

    var _box_w  = 61;
    var _box_gap = 4;
    var _bx0 = _draw_x + 4;
    var _bx1 = _bx0 + _box_w + _box_gap;
    var _bx2 = _bx1 + _box_w + _box_gap;
    var _bx3_9b = _bx2 + _box_w + _box_gap; // 9th-bit checkbox column
    var _cb_size = 10;

    var _slot_start_y = y + 50;
    var _slot_gap_y = 30;
    for (var _si = 0; _si < 8; _si++) {
        var _ry = _slot_start_y + _si * _slot_gap_y;
        var _frames_s = string(instructions[0][2  + _si]);
        var _xs       = string(instructions[0][11 + _si]);
        var _ys       = string(instructions[0][19 + _si]);
        var _active   = (_frames_s != "" && _frames_s != "0");

        // --- Row 1: label + 9bit checkbox ---
        draw_set_font(fnt_c64_nano);
        draw_set_color(_active ? c_yellow : c_gray);
        draw_text(_bx0, _ry, "SPR" + string(_si) + "  FRM             X OFFS           Y OFFS      9thBIT>");

        // --- Row 2: three data boxes ---
        var _ry2 = _ry + 12;
        draw_set_font(fnt_c64_nano);

        // FRAMES box
        var _hov0 = point_in_rectangle(mouse_x, mouse_y, _bx0, _ry2, _bx0 + _box_w, _ry2 + _fld_h);
        draw_set_color(_hov0 ? make_color_rgb(40, 55, 40) : (_active ? make_color_rgb(25, 45, 25) : make_color_rgb(20, 20, 20)));
        draw_rectangle(_bx0, _ry2, _bx0 + _box_w, _ry2 + _fld_h, false);
        draw_set_color(_active ? make_color_rgb(60, 120, 60) : make_color_rgb(40, 40, 40));
        draw_rectangle(_bx0, _ry2, _bx0 + _box_w, _ry2 + _fld_h, true);
        draw_set_color(_active ? c_lime : c_gray);
        draw_set_halign(fa_center);
        var _frm_txt = "-";
        if (_active) {
            _frm_txt = _frames_s;
        }
        var _frm_w = string_width(_frm_txt);
        var _frm_scale = 1;
        if (_frm_w > (_box_w - 6)) {
            _frm_scale = (_box_w - 6) / _frm_w;
        }
        draw_text_transformed(_bx0 + _box_w * 0.5, _ry2 + 2, _frm_txt, _frm_scale, 1, 0);
        draw_set_halign(fa_left);

        // X box
        var _xactive = (_xs != "");
        var _hov1 = point_in_rectangle(mouse_x, mouse_y, _bx1, _ry2, _bx1 + _box_w, _ry2 + _fld_h);
        draw_set_color(_hov1 ? make_color_rgb(55, 40, 40) : (_xactive ? make_color_rgb(45, 25, 25) : make_color_rgb(20, 20, 20)));
        draw_rectangle(_bx1, _ry2, _bx1 + _box_w, _ry2 + _fld_h, false);
        draw_set_color(_xactive ? make_color_rgb(120, 60, 60) : make_color_rgb(40, 40, 40));
        draw_rectangle(_bx1, _ry2, _bx1 + _box_w, _ry2 + _fld_h, true);
        draw_set_color(_xactive ? make_color_rgb(220, 100, 100) : c_gray);
        draw_set_halign(fa_center);
        var _x_txt = "-";
        if (_xactive) {
            _x_txt = _xs;
        }
        var _x_w = string_width(_x_txt);
        var _x_scale = 1;
        if (_x_w > (_box_w - 6)) {
            _x_scale = (_box_w - 6) / _x_w;
        }
        draw_text_transformed(_bx1 + _box_w * 0.5, _ry2 + 2, _x_txt, _x_scale, 1, 0);
        draw_set_halign(fa_left);

        // Y box
        var _yactive = (_ys != "");
        var _hov2 = point_in_rectangle(mouse_x, mouse_y, _bx2, _ry2, _bx2 + _box_w, _ry2 + _fld_h);
        draw_set_color(_hov2 ? make_color_rgb(40, 40, 55) : (_yactive ? make_color_rgb(25, 25, 45) : make_color_rgb(20, 20, 20)));
        draw_rectangle(_bx2, _ry2, _bx2 + _box_w, _ry2 + _fld_h, false);
        draw_set_color(_yactive ? make_color_rgb(60, 60, 120) : make_color_rgb(40, 40, 40));
        draw_rectangle(_bx2, _ry2, _bx2 + _box_w, _ry2 + _fld_h, true);
        draw_set_color(_yactive ? make_color_rgb(100, 100, 220) : c_gray);
        draw_set_halign(fa_center);
        var _y_txt = "-";
        if (_yactive) {
            _y_txt = _ys;
        }
        var _y_w = string_width(_y_txt);
        var _y_scale = 1;
        if (_y_w > (_box_w - 6)) {
            _y_scale = (_box_w - 6) / _y_w;
        }
        draw_text_transformed(_bx2 + _box_w * 0.5, _ry2 + 2, _y_txt, _y_scale, 1, 0);
        draw_set_halign(fa_left);

        // 9th-bit checkbox (writes to instructions[0][27 + _si])
        var _9b_on  = (string(instructions[0][27 + _si]) == "1");
        var _9b_cx  = _bx3_9b;
        var _9b_cy  = _ry2 + 3;
        var _9b_sz  = 10;
        var _hov9b  = point_in_rectangle(mouse_x, mouse_y, _9b_cx, _9b_cy, _9b_cx + _9b_sz, _9b_cy + _9b_sz);
        if (_hov9b) {
            draw_set_color(make_color_rgb(70, 70, 40));
        } else {
            if (_9b_on) {
                draw_set_color(make_color_rgb(120, 100, 30));
            } else {
                draw_set_color(make_color_rgb(30, 30, 30));
            }
        }
        draw_rectangle(_9b_cx, _9b_cy, _9b_cx + _9b_sz, _9b_cy + _9b_sz, false);
        draw_set_color(_9b_on ? make_color_rgb(220, 180, 60) : make_color_rgb(70, 70, 70));
        draw_rectangle(_9b_cx, _9b_cy, _9b_cx + _9b_sz, _9b_cy + _9b_sz, true);
        if (_9b_on) {
            // Draw filled centre to show "on" state clearly
            draw_set_color(make_color_rgb(255, 220, 100));
            draw_rectangle(_9b_cx + 2, _9b_cy + 2, _9b_cx + _9b_sz - 2, _9b_cy + _9b_sz - 2, false);
        }
    }
    draw_set_font(fnt_c64_tiny);

    // ---- Speed / Delay field ----
    var _spd_y    = _slot_start_y + 8 * _slot_gap_y + 4;
    var _loop_val = (string(instructions[0][10]) == "1");
    var _cb_size  = 12;
    var _delay_x2 = _draw_x + 80;

    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_lbl_x, _spd_y, "DELAY:");
    var _shov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _spd_y, _delay_x2, _spd_y + _fld_h);
    draw_set_color(_shov ? make_color_rgb(40, 55, 40) : make_color_rgb(25, 35, 25));
    draw_rectangle(_val_x1, _spd_y, _delay_x2, _spd_y + _fld_h, false);
    draw_set_color(make_color_rgb(60, 100, 60));
    draw_rectangle(_val_x1, _spd_y, _delay_x2, _spd_y + _fld_h, true);
    draw_set_color(make_color_rgb(100, 220, 100));
    draw_set_halign(fa_center);
    draw_text(_val_x1 + (_delay_x2 - _val_x1) * 0.5, _spd_y , string(_speed));
    draw_set_halign(fa_left);

    var _cb_x = _delay_x2 + 40;
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_cb_x - 34, _spd_y , "LOOP:");
    draw_set_color(_loop_val ? make_color_rgb(60, 120, 60) : make_color_rgb(40, 40, 40));
    draw_rectangle(_cb_x+8, _spd_y + 2, _cb_x + _cb_size+8, _spd_y + 2 + _cb_size, false);

    // ---- JSR label ----
    var _footer_y = _spd_y + 20;
    if (!variable_instance_exists(id, "anim_alias") || anim_alias == "")
        anim_alias = "anim" + string(real(id));
    draw_set_color(make_color_rgb(60, 160, 180));
    draw_text(_lbl_x, _footer_y, "JSR:");
    draw_set_color(c_yellow);
    draw_text(_val_x1, _footer_y, anim_alias + "_sub");

    // ---- RESET JSR label + DONE VAR field (one-shot only) ----
    if (!_loop_val) {
        var _reset_y = _footer_y + 14;
        draw_set_color(make_color_rgb(180, 100, 60));
        draw_text(_lbl_x, _reset_y, "RST:");
        draw_set_color(c_yellow);
        draw_text(_val_x1, _reset_y, anim_alias + "_reset");

        // ---- DONE VAR field ----
        var _dv_y    = _reset_y + 14;
        var _dv_name = string(instructions[0][35]);
        var _dv_show = (_dv_name == "" || _dv_name == "[clear]") ? "(none)" : _dv_name;
        var _dv_x2   = _draw_x + width - 8;
        draw_set_color(make_color_rgb(120, 180, 120));
        draw_text(_lbl_x, _dv_y, "DONE:");
        var _dvhov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _dv_y, _dv_x2, _dv_y + _fld_h);
        draw_set_color(_dvhov ? make_color_rgb(40, 55, 40) : make_color_rgb(25, 35, 25));
        draw_rectangle(_val_x1, _dv_y, _dv_x2, _dv_y + _fld_h, false);
        draw_set_color(make_color_rgb(60, 120, 60));
        draw_rectangle(_val_x1, _dv_y, _dv_x2, _dv_y + _fld_h, true);
        draw_set_color(make_color_rgb(120, 220, 120));
        draw_text(_val_x1 + 4, _dv_y + 2, _dv_show);
    }

}