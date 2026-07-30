/// @desc Draw body content for MACRO_SPR_ENABLE node
/// instruction layout:
///   [0] "macro_spr_enable"
///   [1] sprite_mask : 0-255
///   [2] mode        : 0=ENABLE, 1=DISABLE
///
/// Row layout:
///   y+30  : "SPRITES:" label
///   y+44  : 8 toggle buttons
///   y+70  : ENABLE/DISABLE toggle
///   y+100 : byte summary
function scr_node_draw_macro_spr_enable(_draw_x) {
    var _mask = real(instructions[0][1]);
    var _mode = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]))
                ? real(instructions[0][2]) : 0;
    var _bits = [
        ((_mask & 1)   > 0), ((_mask & 2)   > 0),
        ((_mask & 4)   > 0), ((_mask & 8)   > 0),
        ((_mask & 16)  > 0), ((_mask & 32)  > 0),
        ((_mask & 64)  > 0), ((_mask & 128) > 0)
    ];
    // ---- SPRITES label ----
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 27, "SPRITES:          (ONE SHOT CALL)");
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
            draw_set_color((_mode == 0) ? make_color_rgb(20, 180, 80) : make_color_rgb(180, 40, 40));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(c_yellow);
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(50, 60, 50));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(80, 80, 60));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(30, 30, 25));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(60, 60, 50));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        }
        draw_set_halign(fa_center);

        draw_set_color(_on ? c_white : c_gray);
        draw_text(_bx + _btn_w * 0.5, _row1 + 1, string(_si));
        draw_set_halign(fa_left);
    }
    // ---- ENABLE/DISABLE toggle (y+70) ----
    var _row2  = y + 64;
    var _tog_w = 80;
    var _tog_h = 14;
    var _tog_x = _draw_x + 6;
    draw_set_color((_mode == 0) ? make_color_rgb(20, 160, 60) : make_color_rgb(180, 40, 40));
    draw_rectangle(_tog_x, _row2, _tog_x + _tog_w, _row2 + _tog_h, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);

    draw_text(_tog_x + _tog_w * 0.5, _row2 -2, (_mode == 0) ? "ENABLE" : "DISABLE");
    draw_set_halign(fa_left);
    // ---- CLEAR button (to the right of ENABLE/DISABLE toggle) ----
    var _clr_w   = 44;
    var _clr_h   = 14;
    var _clr_x   = _tog_x + _tog_w + 6;
    var _clr_hov = point_in_rectangle(mouse_x, mouse_y, _clr_x, _row2, _clr_x + _clr_w, _row2 + _clr_h);
    if (_clr_hov) {
        draw_set_color(make_color_rgb(80, 60, 20));
        draw_rectangle(_clr_x, _row2, _clr_x + _clr_w, _row2 + _clr_h, false);
        draw_set_color(make_color_rgb(180, 140, 40));
        draw_rectangle(_clr_x, _row2, _clr_x + _clr_w, _row2 + _clr_h, true);
    } else {
        draw_set_color(make_color_rgb(50, 40, 15));
        draw_rectangle(_clr_x, _row2, _clr_x + _clr_w, _row2 + _clr_h, false);
        draw_set_color(make_color_rgb(120, 90, 30));
        draw_rectangle(_clr_x, _row2, _clr_x + _clr_w, _row2 + _clr_h, true);
    }
    draw_set_halign(fa_center);

    draw_set_color(_clr_hov ? c_yellow : c_gray);
    draw_text(_clr_x + _clr_w * 0.5, _row2 -2, "CLEAR");
    draw_set_halign(fa_left);
}