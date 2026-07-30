function scr_node_draw_macro_collision(_draw_x) {
    var _group_a   = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
    var _type      = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _jsr_label = (array_length(instructions[0]) > 3) ? string(instructions[0][3]) : "";
    var _mode      = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
    var _group_b   = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;

    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _bit_values = [1, 2, 4, 8, 16, 32, 64, 128];

    draw_set_font(fnt_c64_tiny);
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)

    // ---- TYPE ----
    draw_set_color(_c_edit);
    draw_text(_draw_x + 6, y + 25, "TYPE:                           (JSR CALLS)");
    var _type_labels = ["SPR-SPR", "SPR-BG", "BOTH"];
    var _tbtn_w = 56;
    for (var _ti = 0; _ti < 3; _ti++) {
        var _bx = _draw_x + 6 + _ti * (_tbtn_w + _btn_gap);
        var _on  = (_type == _ti);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, y + 42, _bx + _tbtn_w, y + 42 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(180, 60, 220));
        } else if (_hov) {
            draw_set_color(make_color_rgb(60, 40, 70));
        } else {
            draw_set_color(make_color_rgb(35, 25, 40));
        }
        draw_rectangle(_bx, y + 42, _bx + _tbtn_w, y + 42 + _btn_h, false);
        if (_on) {
            draw_set_color(c_white);
        } else if (_hov) {
            draw_set_color(c_gray);
        } else {
            draw_set_color(make_color_rgb(80, 60, 90));
        }
        draw_rectangle(_bx, y + 42, _bx + _tbtn_w, y + 42 + _btn_h, true);
        draw_set_halign(fa_center);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _tbtn_w * 0.5, y + 44, _type_labels[_ti]);
        draw_set_halign(fa_left);
    }

    // ---- GROUP A (single sprite select) — orange ----
    draw_set_color(make_color_rgb(220, 140, 40));
    draw_text(_draw_x + 6, y + 70, "SPRITE A: (pick one)");
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = (_group_a == _bit_values[_si]); // single-select: exact match
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, y + 84, _bx + _btn_w, y + 84 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(220, 120, 20));
        } else if (_hov) {
            draw_set_color(make_color_rgb(70, 50, 20));
        } else {
            draw_set_color(make_color_rgb(35, 25, 10));
        }
        draw_rectangle(_bx, y + 84, _bx + _btn_w, y + 84 + _btn_h, false);
        if (_on) {
            draw_set_color(make_color_rgb(255, 160, 60));
        } else {
            draw_set_color(make_color_rgb(80, 60, 30));
        }
        draw_rectangle(_bx, y + 84, _bx + _btn_w, y + 84 + _btn_h, true);
        draw_set_halign(fa_center);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _btn_w * 0.5, y + 86, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- GROUP B (single sprite select, 1-7) — yellow ----
    draw_set_color(make_color_rgb(220, 220, 40));
    draw_text(_draw_x + 6, y + 112, "SPRITE B: (pick one)");
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = (_group_b == _bit_values[_si]); // single-select: exact match
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, y + 126, _bx + _btn_w, y + 126 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(180, 180, 20));
        } else if (_hov) {
            draw_set_color(make_color_rgb(60, 60, 20));
        } else {
            draw_set_color(make_color_rgb(30, 30, 10));
        }
        draw_rectangle(_bx, y + 126, _bx + _btn_w, y + 126 + _btn_h, false);
        if (_on) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(make_color_rgb(80, 80, 30));
        }
        draw_rectangle(_bx, y + 126, _bx + _btn_w, y + 126 + _btn_h, true);
        draw_set_halign(fa_center);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _btn_w * 0.5, y + 128, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- MODE toggle (y+152) ----
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 152, "JSR IF:");
    var _mode_labels = ["HIT", "MISS"];
    var _mbtn_w = 40;
    for (var _mi = 0; _mi < 2; _mi++) {
        var _bx  = _draw_x + 60 + _mi * (_mbtn_w + _btn_gap);
        var _on  = (_mode == _mi);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, y + 152, _bx + _mbtn_w, y + 152 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(180, 60, 220));
        } else if (_hov) {
            draw_set_color(make_color_rgb(60, 40, 70));
        } else {
            draw_set_color(make_color_rgb(35, 25, 40));
        }
        draw_rectangle(_bx, y + 152, _bx + _mbtn_w, y + 152 + _btn_h, false);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(make_color_rgb(80, 60, 90));
        }
        draw_rectangle(_bx, y + 152, _bx + _mbtn_w, y + 152 + _btn_h, true);
        draw_set_halign(fa_center);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _mbtn_w * 0.5, y + 154, _mode_labels[_mi]);
        draw_set_halign(fa_left);
    }

    // ---- JSR LABEL (y+174) ----
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 174, "CALL:");
    var _zx1  = _draw_x + 60;
    var _zx2  = _draw_x + width - 28;
    var _zhov = point_in_rectangle(mouse_x, mouse_y, _zx1, y + 174, _zx2, y + 190);
    if (_zhov) {
        draw_set_color(make_color_rgb(40, 40, 70));
    } else {
        draw_set_color(make_color_rgb(25, 25, 45));
    }
    draw_rectangle(_zx1, y + 174, _zx2, y + 190, false);
    draw_set_color(make_color_rgb(80, 60, 120));
    draw_rectangle(_zx1, y + 174, _zx2, y + 190, true);
    if (_jsr_label != "") {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(c_gray);
    }
    draw_set_halign(fa_center);
    if (_jsr_label != "") {
        draw_text(_zx1 + (_zx2 - _zx1) * 0.5, y + 176, _jsr_label);
    } else {
        draw_text(_zx1 + (_zx2 - _zx1) * 0.5, y + 176, "pick label");
    }
    draw_set_halign(fa_left);

    // Picker button
    var _pbx1 = _zx2 + 2;
    var _pbx2 = _draw_x + width - 4;
    if (point_in_rectangle(mouse_x, mouse_y, _pbx1, y + 174, _pbx2, y + 190)) {
        draw_set_color(make_color_rgb(40, 80, 120));
    } else {
        draw_set_color(make_color_rgb(20, 40, 60));
    }
    draw_rectangle(_pbx1, y + 174, _pbx2, y + 190, false);
    draw_set_color(c_aqua);
    draw_text(_pbx1 + 2, y + 176, "...");
}