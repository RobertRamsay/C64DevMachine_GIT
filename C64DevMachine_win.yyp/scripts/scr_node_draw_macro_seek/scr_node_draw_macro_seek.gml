/// @desc Draw function for MACRO_SEEK node.
/// instruction layout:
///   [0]  "macro_seek"
///   [1]  sprite_mask    : integer 0-255
///   [2]  target_x       : 0..511 (literal, 9th-bit aware)
///   [3]  target_y       : 0..255 (literal)
///   [4]  speed          : 1..255
///   [5]  near_dist      : 0=off, else trigger distance (Manhattan)
///   [6]  speed_near     : 1..255
///   [7]  wide_x         : 0 or 1
///   [8]  bound_mode     : 0=WRAP, 1=BOUNDED
///   [9]  move_mode      : 0=4-DIR, 1=8-DIR, 2=VECTOR
///  [10]  tx_use_var     : 0 or 1
///  [11]  tx_var_name    : string
///  [12]  ty_use_var     : 0 or 1
///  [13]  ty_var_name    : string
///  [14]  dist_out_var   : 0 or 1
///  [15]  dist_var_name  : string
///  [16]  angle_out_var  : 0 or 1
///  [17]  angle_var_name : string
///  [18]  target_sprite  : 0=OFF, 1..8 = target sprite 0..7
function scr_node_draw_macro_seek(_draw_x) {

    // ---- unpack instructions ----
    var _mask    = real(instructions[0][1]);
    var _tx      = (array_length(instructions[0]) > 2  && is_real(instructions[0][2]))  ? real(instructions[0][2])  : 0;
    var _ty      = (array_length(instructions[0]) > 3  && is_real(instructions[0][3]))  ? real(instructions[0][3])  : 0;
    var _spd     = (array_length(instructions[0]) > 4  && is_real(instructions[0][4]))  ? real(instructions[0][4])  : 1;
    var _ndist   = (array_length(instructions[0]) > 5  && is_real(instructions[0][5]))  ? real(instructions[0][5])  : 0;
    var _spdn    = (array_length(instructions[0]) > 6  && is_real(instructions[0][6]))  ? real(instructions[0][6])  : 1;
    var _widex   = (array_length(instructions[0]) > 7  && is_real(instructions[0][7]))  ? real(instructions[0][7])  : 0;
    var _bound   = (array_length(instructions[0]) > 8  && is_real(instructions[0][8]))  ? real(instructions[0][8])  : 0;
    var _mode    = (array_length(instructions[0]) > 9  && is_real(instructions[0][9]))  ? real(instructions[0][9])  : 0;
    var _tx_uv   = (array_length(instructions[0]) > 10 && is_real(instructions[0][10])) ? real(instructions[0][10]) : 0;
    var _tx_vnm  = (array_length(instructions[0]) > 11) ? string(instructions[0][11]) : "";
    var _ty_uv   = (array_length(instructions[0]) > 12 && is_real(instructions[0][12])) ? real(instructions[0][12]) : 0;
    var _ty_vnm  = (array_length(instructions[0]) > 13) ? string(instructions[0][13]) : "";
    var _dist_uv = (array_length(instructions[0]) > 14 && is_real(instructions[0][14])) ? real(instructions[0][14]) : 0;
    var _dist_vnm= (array_length(instructions[0]) > 15) ? string(instructions[0][15]) : "";
    var _ang_uv  = (array_length(instructions[0]) > 16 && is_real(instructions[0][16])) ? real(instructions[0][16]) : 0;
    var _ang_vnm = (array_length(instructions[0]) > 17) ? string(instructions[0][17]) : "";
    var _tspr    = (array_length(instructions[0]) > 18 && is_real(instructions[0][18])) ? real(instructions[0][18]) : 0;

    // ---- build bit array from mask ----
    var _bits = array_create(8);
    for (var _b = 0; _b < 8; _b++) {
        _bits[_b] = (_mask & (1 << _b)) != 0;
    }

    // ---- SPRITES label ----
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 28, "SPRITES:          (ONE SHOT CALL)");

    // ---- 8 toggle buttons ----
    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _row1    = y + 44;

    for (var _si = 0; _si < 8; _si++) {
        var _bx  = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = _bits[_si];

        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(20, 140, 220));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(c_yellow);
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(40, 50, 80));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(50, 60, 80));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(25, 30, 40));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(50, 60, 80));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        }
        draw_set_halign(fa_center);
        draw_set_font(fnt_c64_tiny);
        if (_on) {
            draw_set_color(c_white);
        } else {
            draw_set_color(c_gray);
        }
        draw_text(_bx + _btn_w * 0.5, _row1 + 1, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- shared row geometry ----
    var _but_width_n = 60;            // <-- tune box width here
    var _val_x1 = _draw_x + 60;
    var _val_x2 = _val_x1 + _but_width_n;
    var _tog_x  = _val_x2 + 6;
    var _tog_w  = 30;
    var _var_w  = 28;
    var _var_x  = _tog_x + _tog_w + 4;

    // When a target sprite is bound, X/Y come from VIC; grey the literal/var boxes.
    var _tgt_locked = (_tspr != 0);

    // ---- TARGET X row (y+70) ----
    var _row2 = y + 70;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row2, "TGT X:");

    var _tx_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row2, _val_x2, _row2 + 18);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(28, 28, 32));
    } else if (_tx_uv == 1) {
        if (_tx_hov) {
            draw_set_color(make_color_rgb(70, 60, 30));
        } else {
            draw_set_color(make_color_rgb(45, 38, 18));
        }
    } else {
        if (_tx_hov) {
            draw_set_color(make_color_rgb(50, 70, 90));
        } else {
            draw_set_color(make_color_rgb(30, 42, 55));
        }
    }
    draw_rectangle(_val_x1-17, _row2, _val_x2+17, _row2 + 18, false);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(70, 70, 80));
    } else if (_tx_uv == 1) {
        draw_set_color(make_color_rgb(160, 130, 40));
    } else {
        draw_set_color(make_color_rgb(60, 90, 120));
    }
    draw_rectangle(_val_x1-17, _row2, _val_x2+17, _row2 + 18, true);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(110, 110, 130));
        draw_set_font(fnt_c64_pico);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 3, "SPR " + string(_tspr - 1));
    } else if (_tx_uv == 1) {
        draw_set_color(c_yellow);
        draw_set_font(fnt_c64_pico);
        draw_set_halign(fa_center);
        if (_tx_vnm != "") {
            draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 3, _tx_vnm);
        } else {
            draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 3, "<PICK>");
        }
    } else {
        draw_set_color(make_color_rgb(100, 180, 220));
        draw_set_font(fnt_C64_Angled_tiny);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 2, string(_tx));
    }
    draw_set_halign(fa_left);

    // TGT X VAR toggle
    if (_tx_uv == 1) {
        draw_set_color(make_color_rgb(180, 140, 30));
    } else {
        draw_set_color(make_color_rgb(50, 50, 60));
    }
    draw_rectangle(_var_x, _row2, _var_x + _var_w, _row2 + 16, false);
    if (_tx_uv == 1) {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(make_color_rgb(140, 140, 160));
    }
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    draw_text(_var_x + _var_w * 0.5, _row2 + 2, "VAR");
    draw_set_halign(fa_left);

    // ---- TARGET Y row (y+92) ----
    var _row3 = y + 92;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row3, "TGT Y:");

    var _ty_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row3, _val_x2, _row3 + 18);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(28, 28, 32));
    } else if (_ty_uv == 1) {
        if (_ty_hov) {
            draw_set_color(make_color_rgb(70, 60, 30));
        } else {
            draw_set_color(make_color_rgb(45, 38, 18));
        }
    } else {
        if (_ty_hov) {
            draw_set_color(make_color_rgb(50, 70, 90));
        } else {
            draw_set_color(make_color_rgb(30, 42, 55));
        }
    }
    draw_rectangle(_val_x1-17, _row3, _val_x2+17, _row3 + 18, false);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(70, 70, 80));
    } else if (_ty_uv == 1) {
        draw_set_color(make_color_rgb(160, 130, 40));
    } else {
        draw_set_color(make_color_rgb(60, 90, 120));
    }
    draw_rectangle(_val_x1-17, _row3, _val_x2+17, _row3 + 18, true);
    if (_tgt_locked) {
        draw_set_color(make_color_rgb(110, 110, 130));
        draw_set_font(fnt_c64_pico);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 3, "SPR " + string(_tspr - 1));
    } else if (_ty_uv == 1) {
        draw_set_color(c_yellow);
        draw_set_font(fnt_c64_pico);
        draw_set_halign(fa_center);
        if (_ty_vnm != "") {
            draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 3, _ty_vnm);
        } else {
            draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 3, "<PICK>");
        }
    } else {
        draw_set_color(make_color_rgb(100, 180, 220));
        draw_set_font(fnt_C64_Angled_tiny);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 2, string(_ty));
    }
    draw_set_halign(fa_left);

    // TGT Y VAR toggle
    if (_ty_uv == 1) {
        draw_set_color(make_color_rgb(180, 140, 30));
    } else {
        draw_set_color(make_color_rgb(50, 50, 60));
    }
    draw_rectangle(_var_x, _row3, _var_x + _var_w, _row3 + 16, false);
    if (_ty_uv == 1) {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(make_color_rgb(140, 140, 160));
    }
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    draw_text(_var_x + _var_w * 0.5, _row3 + 2, "VAR");
    draw_set_halign(fa_left);

    // ---- SPEED row (y+114) ----
    var _row4 = y + 114;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row4, "SPEED:");

    var _spd_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row4, _val_x2, _row4 + 18);
    if (_spd_hov) {
        draw_set_color(make_color_rgb(50, 80, 50));
    } else {
        draw_set_color(make_color_rgb(30, 45, 30));
    }
    draw_rectangle(_val_x1, _row4, _val_x2, _row4 + 18, false);
    draw_set_color(make_color_rgb(60, 100, 60));
    draw_rectangle(_val_x1, _row4, _val_x2, _row4 + 18, true);
    draw_set_color(make_color_rgb(100, 220, 100));
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_halign(fa_center);
    draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row4 + 2, string(_spd));
    draw_set_halign(fa_left);

    // MODE toggle (4-DIR / 8-DIR / VECTOR)
    draw_set_color(make_color_rgb(120, 60, 160));
    draw_rectangle(_tog_x, _row4, _tog_x + _tog_w + _var_w + 4, _row4 + 16, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    var _mode_txt = "4-DIR";
    if (_mode != 0) {
        _mode_txt = "8-DIR";
    }
    draw_text(_tog_x + (_tog_w + _var_w + 4) * 0.5, _row4 + 2, _mode_txt);
    draw_set_halign(fa_left);

    // ---- NEAR DIST row (y+136) ----
    var _row5 = y + 136;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row5, "NEAR:");

    var _nd_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row5, _val_x2, _row5 + 18);
    if (_nd_hov) {
        draw_set_color(make_color_rgb(80, 70, 40));
    } else {
        draw_set_color(make_color_rgb(50, 44, 25));
    }
    draw_rectangle(_val_x1, _row5, _val_x2, _row5 + 18, false);
    draw_set_color(make_color_rgb(120, 100, 50));
    draw_rectangle(_val_x1, _row5, _val_x2, _row5 + 18, true);
    draw_set_color(make_color_rgb(230, 200, 100));
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_halign(fa_center);
    if (_ndist == 0) {
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row5 + 2, "OFF");
    } else {
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row5 + 2, string(_ndist));
    }
    draw_set_halign(fa_left);

    // SPD-NEAR box (reuses tog area)
    var _spdn_hov = point_in_rectangle(mouse_x, mouse_y, _tog_x, _row5, _tog_x + _tog_w + _var_w + 4, _row5 + 18);
    if (_ndist == 0) {
        draw_set_color(make_color_rgb(35, 35, 35));
    } else if (_spdn_hov) {
        draw_set_color(make_color_rgb(50, 80, 50));
    } else {
        draw_set_color(make_color_rgb(30, 45, 30));
    }
    draw_rectangle(_tog_x, _row5, _tog_x + _tog_w + _var_w + 4, _row5 + 18, false);
    draw_set_color(make_color_rgb(60, 100, 60));
    draw_rectangle(_tog_x, _row5, _tog_x + _tog_w + _var_w + 4, _row5 + 18, true);
    if (_ndist == 0) {
        draw_set_color(make_color_rgb(90, 90, 90));
    } else {
        draw_set_color(make_color_rgb(100, 220, 100));
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_text(_tog_x + (_tog_w + _var_w + 4) * 0.5, _row5 + 2, "+SPD " + string(_spdn));
    draw_set_halign(fa_left);

   // ---- DIST OUT row (y+158) ----
    var _row6 = y + 158;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row6, "DIST>");

    var _out_bx1 = _draw_x + 50;
    var _out_bx2 = _out_bx1 + _but_width_n + 30;
    var _dist_hov = point_in_rectangle(mouse_x, mouse_y, _out_bx1, _row6, _out_bx2, _row6 + 18);
    if (_dist_uv == 1) {
        if (_dist_hov) {
            draw_set_color(make_color_rgb(70, 60, 30));
        } else {
            draw_set_color(make_color_rgb(45, 38, 18));
        }
    } else {
        if (_dist_hov) {
            draw_set_color(make_color_rgb(50, 50, 60));
        } else {
            draw_set_color(make_color_rgb(35, 35, 45));
        }
    }
    draw_rectangle(_out_bx1, _row6, _out_bx2, _row6 + 18, false);
    if (_dist_uv == 1) {
        draw_set_color(make_color_rgb(160, 130, 40));
    } else {
        draw_set_color(make_color_rgb(70, 70, 90));
    }
    draw_rectangle(_out_bx1, _row6, _out_bx2, _row6 + 18, true);
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_halign(fa_center);
    if (_dist_uv == 1) {
        draw_set_color(c_yellow);
        if (_dist_vnm != "") {
            draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row6 + 3, _dist_vnm);
        } else {
            draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row6 + 3, "<PICK>");
        }
    } else {
        draw_set_color(make_color_rgb(120, 120, 150));
        draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row6 + 3, "OFF");
    }
    draw_set_halign(fa_left);

    // ---- ANGLE OUT row (y+180) ----
    var _row7 = y + 180;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row7, "ANG>");

    var _ang_hov = point_in_rectangle(mouse_x, mouse_y, _out_bx1, _row7, _out_bx2, _row7 + 18);
    if (_ang_uv == 1) {
        if (_ang_hov) {
            draw_set_color(make_color_rgb(70, 60, 30));
        } else {
            draw_set_color(make_color_rgb(45, 38, 18));
        }
    } else {
        if (_ang_hov) {
            draw_set_color(make_color_rgb(50, 50, 60));
        } else {
            draw_set_color(make_color_rgb(35, 35, 45));
        }
    }
    draw_rectangle(_out_bx1, _row7, _out_bx2, _row7 + 18, false);
    if (_ang_uv == 1) {
        draw_set_color(make_color_rgb(160, 130, 40));
    } else {
        draw_set_color(make_color_rgb(70, 70, 90));
    }
    draw_rectangle(_out_bx1, _row7, _out_bx2, _row7 + 18, true);
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_halign(fa_center);
    if (_ang_uv == 1) {
        draw_set_color(c_yellow);
        if (_ang_vnm != "") {
            draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row7 + 3, _ang_vnm);
        } else {
            draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row7 + 3, "<PICK>");
        }
    } else {
        draw_set_color(make_color_rgb(120, 120, 150));
        draw_text(_out_bx1 + (_out_bx2 - _out_bx1) / 2, _row7 + 3, "OFF");
    }
    draw_set_halign(fa_left);

    // ---- Wide-X + BOUND row (y+202) ----
    var _row8   = y + 202;
    var _chk_sz = 12;

    // 9th-bit checkbox
    if (_widex) {
        draw_set_color(make_color_rgb(20, 140, 220));
    } else {
        draw_set_color(make_color_rgb(25, 30, 40));
    }
    draw_rectangle(_draw_x + 6, _row8 + 2, _draw_x + 6 + _chk_sz, _row8 + _chk_sz + 2, false);
    draw_set_color(make_color_rgb(60, 90, 120));
    draw_rectangle(_draw_x + 6, _row8 + 2, _draw_x + 6 + _chk_sz, _row8 + _chk_sz + 2, true);
    if (_widex) {
        draw_set_color(c_white);
        draw_line(_draw_x + 8,  _row8 + 6,  _draw_x + 11, _row8 + 10);
        draw_line(_draw_x + 11, _row8 + 10, _draw_x + 17, _row8 + 2);
    }
    draw_set_font(fnt_c64_tiny);
    if (_widex) {
        draw_set_color(make_color_rgb(100, 180, 240));
    } else {
        draw_set_color(make_color_rgb(90, 100, 120));
    }
    draw_text(_draw_x + 6 + _chk_sz + 5, _row8, "9TH BIT");

    // WRAP/BOUNDED toggle
    var _bnd_x = _draw_x + 90;
    if (_bound == 1) {
        draw_set_color(make_color_rgb(200, 120, 40));
    } else {
        draw_set_color(make_color_rgb(40, 120, 160));
    }
    draw_rectangle(_bnd_x, _row8, _bnd_x + 70, _row8 + 16, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    if (_bound == 1) {
        draw_text(_bnd_x + 35, _row8 + 2, "BOUNDED");
    } else {
        draw_text(_bnd_x + 35, _row8 + 2, "WRAP");
    }
    draw_set_halign(fa_left);

    // ---- TGT SPRITE button ----
    var _tspr_x = _draw_x + 144;
    if (_tspr != 0) {
        draw_set_color(make_color_rgb(160, 60, 60));
    } else {
        draw_set_color(make_color_rgb(40, 50, 60));
    }
    draw_rectangle(_tspr_x, _row6, _tspr_x + 44, _row6 + 40, false);
    draw_set_color(make_color_rgb(200, 120, 120));
    draw_rectangle(_tspr_x, _row6, _tspr_x + 44, _row6 + 40, true);
    if (_tspr != 0) {
        draw_set_color(c_white);
    } else {
        draw_set_color(make_color_rgb(110, 120, 140));
    }
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_pico);
    if (_tspr != 0) {
        draw_text(_tspr_x + 21, _row6 + 2, "TARGET\nSPRITE\n  " + string(_tspr - 1));
    } else {
        draw_text(_tspr_x + 21, _row6 + 2, "TARGET\nSPRITE\nOFF");
    }
    draw_set_halign(fa_left);
}