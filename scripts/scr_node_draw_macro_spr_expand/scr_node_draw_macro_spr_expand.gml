/// @desc Draw body content for MACRO_SPR_EXPAND node
/// instruction layout:
///   [0] "macro_spr_expand"
///   [1] x_expand_mask : 0-255  -> $D01D
///   [2] y_expand_mask : 0-255  -> $D017
///
/// Row layout:
///   y+27  : "X EXPAND:" label
///   y+44  : 8 X expand toggle buttons
///   y+59  : "Y EXPAND:" label
///   y+76  : 8 Y expand toggle buttons
///   y+110 : CLEAR button
function scr_node_draw_macro_spr_expand(_draw_x) {
    var _x_mask = real(instructions[0][1]);
    var _y_mask = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]))
                  ? real(instructions[0][2]) : 0;
    var _x_bits = [
        ((_x_mask & 1)   > 0), ((_x_mask & 2)   > 0),
        ((_x_mask & 4)   > 0), ((_x_mask & 8)   > 0),
        ((_x_mask & 16)  > 0), ((_x_mask & 32)  > 0),
        ((_x_mask & 64)  > 0), ((_x_mask & 128) > 0)
    ];
    var _y_bits = [
        ((_y_mask & 1)   > 0), ((_y_mask & 2)   > 0),
        ((_y_mask & 4)   > 0), ((_y_mask & 8)   > 0),
        ((_y_mask & 16)  > 0), ((_y_mask & 32)  > 0),
        ((_y_mask & 64)  > 0), ((_y_mask & 128) > 0)
    ];
    var _btn_w   = 22;
    var _btn_h   = 18;
    var _btn_gap = 2;
    var _btn_sx  = _draw_x + 6;
    var _row1    = y + 44;
    var _row2    = y + 76;
    draw_set_font(fnt_c64_tiny);
    // ---- X EXPAND label ----
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 27, "X EXPAND:        (ONE SHOT CALL)");
    // ---- X EXPAND 8 toggle buttons ----
    for (var _si = 0; _si < 8; _si++) {
        var _bx  = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = _x_bits[_si];
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(40, 120, 200));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(c_yellow);
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(40, 50, 70));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(70, 80, 110));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(25, 30, 40));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(55, 65, 85));
            draw_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        }
        draw_set_halign(fa_center);
        draw_set_color(_on ? c_white : c_gray);
        draw_text(_bx + _btn_w * 0.5, _row1 + 1, string(_si));
        draw_set_halign(fa_left);
    }
    // ---- Y EXPAND label ----
    draw_set_color(make_color_rgb(160, 160, 160));
    draw_text(_draw_x + 6, y + 59, "Y EXPAND:");
    // ---- Y EXPAND 8 toggle buttons ----
    for (var _si = 0; _si < 8; _si++) {
        var _bx  = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = _y_bits[_si];
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _row2, _bx + _btn_w, _row2 + _btn_h);
        if (_on) {
            draw_set_color(make_color_rgb(180, 80, 200));
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, false);
            draw_set_color(c_yellow);
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(60, 40, 70));
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, false);
            draw_set_color(make_color_rgb(100, 70, 110));
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(35, 25, 40));
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, false);
            draw_set_color(make_color_rgb(75, 55, 85));
            draw_rectangle(_bx, _row2, _bx + _btn_w, _row2 + _btn_h, true);
        }
        draw_set_halign(fa_center);
        draw_set_color(_on ? c_white : c_gray);
        draw_text(_bx + _btn_w * 0.5, _row2 + 1, string(_si));
        draw_set_halign(fa_left);
    }
    // ---- CLEAR button ----
    var _clr_w   = 44;
    var _clr_h   = 14;
    var _clr_x   = _btn_sx + 8 * (_btn_w + _btn_gap) - _btn_gap - _clr_w;
    var _clr_y   = y + 102;
    var _clr_hov = point_in_rectangle(mouse_x, mouse_y, _clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h);
    if (_clr_hov) {
        draw_set_color(make_color_rgb(80, 60, 20));
        draw_rectangle(_clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h, false);
        draw_set_color(make_color_rgb(180, 140, 40));
        draw_rectangle(_clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h, true);
    } else {
        draw_set_color(make_color_rgb(50, 40, 15));
        draw_rectangle(_clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h, false);
        draw_set_color(make_color_rgb(120, 90, 30));
        draw_rectangle(_clr_x, _clr_y, _clr_x + _clr_w, _clr_y + _clr_h, true);
    }
    draw_set_halign(fa_center);
    draw_set_color(_clr_hov ? c_yellow : c_gray);
    draw_text(_clr_x + _clr_w * 0.5, _clr_y - 2, "CLEAR");
    draw_set_halign(fa_left);
}