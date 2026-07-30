/// @desc scr_node_draw_macro_get_char(_draw_x, _y)
/// instructions[0]: ["macro_get_char",
///   1 col_lit, 2 col_vmode, 3 col_var,
///   4 row_lit, 5 row_vmode, 6 row_var,
///   7 dst_var, 8 get_col, 9 dst_col_var,
///   10 scr_base, 11 zp_base]

function scr_node_draw_macro_get_char(_draw_x, _y) {

    var _ins = instructions[0];

    var _col_lit   = (array_length(_ins) > 1  && is_real(_ins[1]))  ? real(_ins[1])  : 0;
    var _col_vmode = (array_length(_ins) > 2  && is_real(_ins[2]))  ? real(_ins[2])  : 0;
    var _col_var   = (array_length(_ins) > 3)  ? string(_ins[3])  : "";
    var _row_lit   = (array_length(_ins) > 4  && is_real(_ins[4]))  ? real(_ins[4])  : 0;
    var _row_vmode = (array_length(_ins) > 5  && is_real(_ins[5]))  ? real(_ins[5])  : 0;
    var _row_var   = (array_length(_ins) > 6)  ? string(_ins[6])  : "";
    var _dst_var   = (array_length(_ins) > 7)  ? string(_ins[7])  : "";
    var _get_col   = (array_length(_ins) > 8  && is_real(_ins[8]))  ? real(_ins[8])  : 0;
    var _dcol_var  = (array_length(_ins) > 9)  ? string(_ins[9])  : "";
    var _scr_base  = (array_length(_ins) > 10 && is_real(_ins[10])) ? real(_ins[10]) : 0x0400;
    var _zp        = (array_length(_ins) > 11 && is_real(_ins[11])) ? real(_ins[11]) : 0xFB;

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

    // ── Row 3: DEST var (receives screencode) ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "-> CHR:");
    if (_dst_var != "") {
        draw_set_color(c_lime);
        draw_text(_draw_x + 66, _ly, _dst_var);
    } else {
        draw_set_color(c_orange);
        draw_text(_draw_x + 66, _ly, "-pick var-");
    }
    _ly += _lh;

    // ── Row 4: GET COL checkbox ──
    var _cbx = _draw_x + 10;
    if (_get_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_get_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx + 18, _ly, "ALSO READ COLOUR");
    _ly += _lh;

    // ── Row 5: DEST colour var ──
    if (_get_col == 1) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "-> COL:");
        if (_dcol_var != "") {
            draw_set_color(c_lime);
            draw_text(_draw_x + 66, _ly, _dcol_var);
        } else {
            draw_set_color(c_orange);
            draw_text(_draw_x + 66, _ly, "-pick var-");
        }
    } else {
        draw_set_color(make_color_rgb(60, 60, 70));
        draw_text(_draw_x + 10, _ly, "-> COL: -");
    }
    _ly += _lh;

    // ── Row 6: SCR BASE + ZP ──
    var _sb_hex = decimal_to_hex(_scr_base);
    while (string_length(_sb_hex) < 4) _sb_hex = "0" + _sb_hex;
    var _zp_hex = decimal_to_hex(_zp);
    while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;

    var _sb_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 10);
    var _zp_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 11);

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

    // ── Footer ──
    var _zp2 = decimal_to_hex(_zp + 3);
    while (string_length(_zp2) < 2) _zp2 = "0" + _zp2;
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    if (_col_vmode == 0 && _row_vmode == 0) {
        var _cell = _scr_base + (_row_lit * 40) + _col_lit;
        var _ch   = decimal_to_hex(_cell);
        while (string_length(_ch) < 4) _ch = "0" + _ch;
        draw_text(_draw_x + 8, _ly, "READS $" + string_upper(_ch) + "   ZP $" + string_upper(_zp_hex) + "-$" + string_upper(_zp2));
    } else {
        draw_text(_draw_x + 8, _ly, "READS RUNTIME   ZP $" + string_upper(_zp_hex) + "-$" + string_upper(_zp2));
    }
}