/// @desc scr_node_draw_macro_place_char(_draw_x, _y)
/// instructions[0]: ["macro_place_char",
///   1 col_lit, 2 col_vmode, 3 col_var,
///   4 row_lit, 5 row_vmode, 6 row_var,
///   7 char_src (0=LIT 1=VAR 2=ASSET), 8 char_lit, 9 char_var, 10 char_asset,
///   11 idx_vmode, 12 idx_lit, 13 idx_var,
///   14 set_col, 15 col_val, 16 scr_base, 17 zp_base]

function scr_node_draw_macro_place_char(_draw_x, _y) {

    var _ins = instructions[0];

    var _col_lit   = (array_length(_ins) > 1  && is_real(_ins[1]))  ? real(_ins[1])  : 0;
    var _col_vmode = (array_length(_ins) > 2  && is_real(_ins[2]))  ? real(_ins[2])  : 0;
    var _col_var   = (array_length(_ins) > 3)  ? string(_ins[3])  : "";
    var _row_lit   = (array_length(_ins) > 4  && is_real(_ins[4]))  ? real(_ins[4])  : 0;
    var _row_vmode = (array_length(_ins) > 5  && is_real(_ins[5]))  ? real(_ins[5])  : 0;
    var _row_var   = (array_length(_ins) > 6)  ? string(_ins[6])  : "";
    var _chr_src   = (array_length(_ins) > 7  && is_real(_ins[7]))  ? real(_ins[7])  : 0;
    var _chr_lit   = (array_length(_ins) > 8  && is_real(_ins[8]))  ? real(_ins[8])  : 32;
    var _chr_var   = (array_length(_ins) > 9)  ? string(_ins[9])  : "";
    var _chr_asset = (array_length(_ins) > 10) ? string(_ins[10]) : "";
    var _idx_vmode = (array_length(_ins) > 11 && is_real(_ins[11])) ? real(_ins[11]) : 0;
    var _idx_lit   = (array_length(_ins) > 12 && is_real(_ins[12])) ? real(_ins[12]) : 0;
    var _idx_var   = (array_length(_ins) > 13) ? string(_ins[13]) : "";
    var _set_col   = (array_length(_ins) > 14 && is_real(_ins[14])) ? real(_ins[14]) : 1;
    var _col_val   = (array_length(_ins) > 15 && is_real(_ins[15])) ? clamp(real(_ins[15]), 0, 15) : 1;
    var _scr_base  = (array_length(_ins) > 16 && is_real(_ins[16])) ? real(_ins[16]) : 0x0400;
    var _zp        = (array_length(_ins) > 17 && is_real(_ins[17])) ? real(_ins[17]) : 0xFB;

    var _lh = 14;
    var _ly = _y + 28;

    var _c_lbl  = make_color_rgb(140, 160, 200);
    var _c_dim  = make_color_rgb(100, 100, 100);
    var _vbtn_w = 28;

    draw_set_font(fnt_c64_tiny);

    // ── Row 1: COL ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "COL:");
    if (_col_vmode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 52, _ly, (_col_var != "") ? _col_var : "<PICK>");
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 52, _ly, string(_col_lit));
    }
    var _cvx = _draw_x + width - 38;
    if (_col_vmode == 1) {
        draw_set_color(make_color_rgb(180, 140, 30));
    } else {
        draw_set_color(make_color_rgb(50, 50, 60));
    }
    draw_rectangle(_cvx, _ly + 1, _cvx + _vbtn_w, _ly + 12, false);
    if (_col_vmode == 1) {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(make_color_rgb(140, 140, 160));
    }
    draw_set_halign(fa_center);
    draw_text(_cvx + (_vbtn_w * 0.5), _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ── Row 2: ROW ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "ROW:");
    if (_row_vmode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 52, _ly, (_row_var != "") ? _row_var : "<PICK>");
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 52, _ly, string(_row_lit));
    }
    var _rvx = _draw_x + width - 38;
    if (_row_vmode == 1) {
        draw_set_color(make_color_rgb(180, 140, 30));
    } else {
        draw_set_color(make_color_rgb(50, 50, 60));
    }
    draw_rectangle(_rvx, _ly + 1, _rvx + _vbtn_w, _ly + 12, false);
    if (_row_vmode == 1) {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(make_color_rgb(140, 140, 160));
    }
    draw_set_halign(fa_center);
    draw_text(_rvx + (_vbtn_w * 0.5), _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ── Row 3: CHAR SRC toggle ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "SRC:");
    var _src_lbl = "LITERAL";
    if (_chr_src == 1) {
        _src_lbl = "VARIABLE";
    } else if (_chr_src == 2) {
        _src_lbl = "BYTE DATA";
    }
    var _sbx1 = _draw_x + 52;
    var _sbx2 = _draw_x + width - 10;
    draw_set_color(make_color_rgb(40, 60, 90));
    draw_rectangle(_sbx1, _ly + 1, _sbx2, _ly + 13, false);
    draw_set_color(c_aqua);
    draw_text(_sbx1 + 6, _ly, _src_lbl);
    _ly += _lh;

    // ── Row 4: char value / var / asset ──
    if (_chr_src == 0) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "CHR:");
        draw_set_color(c_lime);
        var _ch_hex = decimal_to_hex(_chr_lit & 0xFF);
        while (string_length(_ch_hex) < 2) _ch_hex = "0" + _ch_hex;
        draw_text(_draw_x + 52, _ly, "$" + string_upper(_ch_hex) + "  (" + string(_chr_lit) + ")");
    } else if (_chr_src == 1) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "CHR:");
        if (_chr_var != "") {
            draw_set_color(c_lime);
            draw_text(_draw_x + 52, _ly, _chr_var);
        } else {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 52, _ly, "-pick var-");
        }
    } else {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "SET:");
        if (_chr_asset != "") {
            draw_set_color(c_lime);
            draw_text(_draw_x + 52, _ly, _chr_asset);
        } else {
            draw_set_color(c_orange);
            draw_text(_draw_x + 52, _ly, "< NONE >");
        }
    }
    _ly += _lh;

    // ── Row 5: asset index (BYTE_DATA mode only) ──
    if (_chr_src == 2) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "IDX:");
        if (_idx_vmode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 52, _ly, (_idx_var != "") ? _idx_var : "<PICK>");
        } else {
            draw_set_color(c_aqua);
            draw_text(_draw_x + 52, _ly, string(_idx_lit));
        }
        var _ivx = _draw_x + width - 38;
        if (_idx_vmode == 1) {
            draw_set_color(make_color_rgb(180, 140, 30));
        } else {
            draw_set_color(make_color_rgb(50, 50, 60));
        }
        draw_rectangle(_ivx, _ly + 1, _ivx + _vbtn_w, _ly + 12, false);
        if (_idx_vmode == 1) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(make_color_rgb(140, 140, 160));
        }
        draw_set_halign(fa_center);
        draw_text(_ivx + (_vbtn_w * 0.5), _ly, "VAR");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(make_color_rgb(60, 60, 70));
        draw_text(_draw_x + 10, _ly, "IDX: -");
    }
    _ly += _lh;

    // ── Row 6: SET COLOUR checkbox + swatch ──
    var _cbx = _draw_x + 10;
    if (_set_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_set_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx + 18, _ly, "SET COL");

    if (_set_col == 1) {
        draw_set_color(scr_c64_pepto_colour(_col_val));
        draw_rectangle(_draw_x + 100, _ly + 2, _draw_x + 120, _ly + 13, false);
        draw_set_color(c_gray);
        draw_rectangle(_draw_x + 100, _ly + 2, _draw_x + 120, _ly + 13, true);
        draw_set_color(c_yellow);
        draw_text(_draw_x + 126, _ly, string(_col_val));
    }
    _ly += _lh;

    // ── Row 7: SCR BASE + ZP ──
    var _sb_hex = decimal_to_hex(_scr_base);
    while (string_length(_sb_hex) < 4) _sb_hex = "0" + _sb_hex;
    var _zp_hex = decimal_to_hex(_zp);
    while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;

    var _sb_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 16);
    var _zp_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 17);

    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "BASE:");
    if (_sb_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, "$" + obj_workspace_manager.current_input_string);
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 52, _ly, "$" + string_upper(_sb_hex));
    }

    draw_set_color(_c_lbl);
    draw_text(_draw_x + 118, _ly, "ZP:");
    if (_zp_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 146, _ly, "$" + obj_workspace_manager.current_input_string);
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 146, _ly, "$" + string_upper(_zp_hex));
    }
    _ly += _lh;

    // ── Footer: resolved cell + ZP footprint ──
    var _zp2 = decimal_to_hex(_zp + 3);
    while (string_length(_zp2) < 2) _zp2 = "0" + _zp2;
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    if (_col_vmode == 0 && _row_vmode == 0) {
        var _cell = _scr_base + (_row_lit * 40) + _col_lit;
        var _ch   = decimal_to_hex(_cell);
        while (string_length(_ch) < 4) _ch = "0" + _ch;
        draw_text(_draw_x + 8, _ly, "CELL $" + string_upper(_ch) + "   ZP $" + string_upper(_zp_hex) + "-$" + string_upper(_zp2));
    } else {
        draw_text(_draw_x + 8, _ly, "CELL RUNTIME   ZP $" + string_upper(_zp_hex) + "-$" + string_upper(_zp2));
    }
}