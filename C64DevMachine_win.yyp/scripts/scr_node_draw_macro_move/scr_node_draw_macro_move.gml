/// @desc Draw function for MACRO_MOVE node.
/// instruction layout:
///   [0] "macro_move"
///   [1] sprite_mask  : integer 0-255, bits 0-7
///   [2] dx           : signed -128..+127 (literal)
///   [3] dy           : signed -128..+127 (literal)
///   [4] wide_x       : 0 or 1
///   [5] dx_mode      : 0=WRAP, 1=STOP
///   [6] dy_mode      : 0=WRAP, 1=STOP
///   [7] dx_use_var   : 0 or 1
///   [8] dx_var_name  : string
///   [9] dy_use_var   : 0 or 1
///  [10] dy_var_name  : string
function scr_node_draw_macro_move(_draw_x) {

    // ---- unpack instructions ----
    var _mask   = real(instructions[0][1]);
    var _dx     = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _dy     = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 0;
    var _widex  = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0;
    var _dx_mod = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0;
    var _dy_mod = (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) ? real(instructions[0][6]) : 0;
    var _dx_uv  = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 0;
    var _dx_vnm = (array_length(instructions[0]) > 8) ? string(instructions[0][8]) : "";
    var _dy_uv  = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
    var _dy_vnm = (array_length(instructions[0]) > 10) ? string(instructions[0][10]) : "";

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
            draw_set_color(make_color_rgb(220, 80, 20));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(c_yellow);
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(80, 50, 40));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(80, 60, 50));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(40, 30, 25));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(80, 60, 50));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        }
        draw_set_halign(fa_center);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_on ? c_white : c_gray);
        draw_text(_bx + _btn_w * 0.5, _row1 + 1, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- shared row geometry ----
    var _tw     = 34;
    var _th     = 16;
    var _val_x1 = _draw_x + 38;
    var _val_x2 = _draw_x + 120;
    var _tog_x  = _val_x2 + 4;
    var _var_w  = 28;
    var _var_x  = _tog_x + _tw + 4;

    // ---- DX row (y+70) ----
    var _row2 = y + 70;
    draw_set_font(fnt_C64_Angled);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row2, "DX:");

    var _dx_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row2, _val_x2, _row2 + 18);
    if (_dx_uv == 1) {
        // Var mode — yellow box like GET_VAR style
        draw_set_color(_dx_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_dx_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 45, 30));
    }
    draw_rectangle(_val_x1, _row2, _val_x2, _row2 + 18, false);
    draw_set_color((_dx_uv == 1) ? make_color_rgb(160, 130, 40) : make_color_rgb(60, 100, 60));
    draw_rectangle(_val_x1, _row2, _val_x2, _row2 + 18, true);
    if (_dx_uv == 1) {
        draw_set_color(c_yellow);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 3, (_dx_vnm != "") ? _dx_vnm : "<PICK>");
    } else {
        draw_set_color(make_color_rgb(100, 220, 100));
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row2 + 2, string(_dx));
    }
    draw_set_halign(fa_left);

    // WRAP/STOP toggle
    draw_set_color((_dx_mod == 1) ? make_color_rgb(200, 60, 60) : make_color_rgb(40, 120, 160));
    draw_rectangle(_tog_x, _row2, _tog_x + _tw, _row2 + _th, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    draw_text(_tog_x + _tw * 0.5, _row2 + 2, (_dx_mod == 1) ? "STOP" : "WRAP");

    // VAR toggle
    draw_set_color((_dx_uv == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
    draw_rectangle(_var_x, _row2, _var_x + _var_w, _row2 + _th, false);
    draw_set_color((_dx_uv == 1) ? c_yellow : make_color_rgb(140, 140, 160));
    draw_text(_var_x + _var_w * 0.5, _row2 + 2, "VAR");
    draw_set_halign(fa_left);

    // ---- DY row (y+92) ----
    var _row3 = y + 92;
    draw_set_font(fnt_C64_Angled);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, _row3, "DY:");

    var _dy_hov = point_in_rectangle(mouse_x, mouse_y, _val_x1, _row3, _val_x2, _row3 + 18);
    if (_dy_uv == 1) {
        draw_set_color(_dy_hov ? make_color_rgb(70, 60, 30) : make_color_rgb(45, 38, 18));
    } else {
        draw_set_color(_dy_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 45, 30));
    }
    draw_rectangle(_val_x1, _row3, _val_x2, _row3 + 18, false);
    draw_set_color((_dy_uv == 1) ? make_color_rgb(160, 130, 40) : make_color_rgb(60, 100, 60));
    draw_rectangle(_val_x1, _row3, _val_x2, _row3 + 18, true);
    if (_dy_uv == 1) {
        draw_set_color(c_yellow);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 3, (_dy_vnm != "") ? _dy_vnm : "<PICK>");
    } else {
        draw_set_color(make_color_rgb(100, 220, 100));
        draw_set_halign(fa_center);
        draw_text(_val_x1 + (_val_x2 - _val_x1) / 2, _row3 + 2, string(_dy));
    }
    draw_set_halign(fa_left);

    // WRAP/STOP toggle
    draw_set_color((_dy_mod == 1) ? make_color_rgb(200, 60, 60) : make_color_rgb(40, 120, 160));
    draw_rectangle(_tog_x, _row3, _tog_x + _tw, _row3 + _th, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    draw_text(_tog_x + _tw * 0.5, _row3 + 2, (_dy_mod == 1) ? "STOP" : "WRAP");

    // VAR toggle
    draw_set_color((_dy_uv == 1) ? make_color_rgb(180, 140, 30) : make_color_rgb(50, 50, 60));
    draw_rectangle(_var_x, _row3, _var_x + _var_w, _row3 + _th, false);
    draw_set_color((_dy_uv == 1) ? c_yellow : make_color_rgb(140, 140, 160));
    draw_text(_var_x + _var_w * 0.5, _row3 + 2, "VAR");
    draw_set_halign(fa_left);

    // ---- Wide-X checkbox (y+114) ----
    var _row4   = y + 114;
    var _chk_sz = 12;
    if (_widex) {
        draw_set_color(make_color_rgb(220, 80, 20));
    } else {
        draw_set_color(make_color_rgb(40, 30, 25));
    }
    draw_rectangle(_draw_x + 6, _row4 + 2, _draw_x + 6 + _chk_sz, _row4 + _chk_sz + 2, false);
    draw_set_color(make_color_rgb(120, 80, 60));
    draw_rectangle(_draw_x + 6, _row4 + 2, _draw_x + 6 + _chk_sz, _row4 + _chk_sz + 2, true);
    if (_widex) {
        draw_set_color(c_white);
        draw_line(_draw_x + 8,  _row4 + 6,  _draw_x + 11, _row4 + 10);
        draw_line(_draw_x + 11, _row4 + 10, _draw_x + 17, _row4 + 2);
    }
    draw_set_font(fnt_c64_tiny);
    if (_widex) {
        draw_set_color(make_color_rgb(255, 160, 60));
    } else {
        draw_set_color(make_color_rgb(120, 100, 80));
    }
    draw_text(_draw_x + 6 + _chk_sz + 5, _row4, "9TH BIT (X>255)");
}