/// instruction layout:
///   [0] "macro_priority"
///   [1] sprite_mask : 0–255
///   [2] mode        : 0=FRONT, 1=BEHIND
///
/// Row layout:
///   y+24  : body bg
///   y+30  : "SPRITES:" label
///   y+44  : 8 toggle buttons
///   y+70  : FRONT/BEHIND toggle
///   y+100 : byte summary
///   y+114 : node bottom → height=114

function scr_node_draw_macro_priority(_draw_x) {

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
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    scr_node_macro_text_l(_draw_x + 6, y + 27, "SPRITES:          (ONE SHOT CALL)");

    // ---- 8 toggle buttons ----
    var _btn_w = 22, _btn_h = 18, _btn_gap = 2;
    var _btn_sx = _draw_x + 6;
    var _row1   = y + 44;

    for (var _si = 0; _si < 8; _si++) {
        var _bx  = _btn_sx + _si * (_btn_w + _btn_gap);
        var _on  = _bits[_si];
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _row1, _bx + _btn_w, _row1 + _btn_h);

        if (_on) {
            draw_set_color(make_color_rgb(220, 80, 20));
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(c_yellow);
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else if (_hov) {
            draw_set_color(make_color_rgb(80, 50, 40));
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(80, 60, 50));
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        } else {
            draw_set_color(make_color_rgb(40, 30, 25));
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, false);
            draw_set_color(make_color_rgb(80, 60, 50));
            scr_macro_body_rectangle(_bx, _row1, _bx + _btn_w, _row1 + _btn_h, true);
        }
        draw_set_halign(fa_center);
        draw_set_font_l(fnt_c64_tiny);
        draw_set_color(_on ? c_white : c_gray);
        scr_node_macro_text_l(_bx + _btn_w * 0.5, _row1 + 3, string(_si));
        draw_set_halign(fa_left);
    }

    // ---- FRONT/BEHIND toggle (y+70) ----
    var _row2  = y + 64;
    var _tog_w = 80;
    var _tog_h = 14;
    var _tog_x = _draw_x + 6;

    if (_mode == 1) {
        draw_set_color(make_color_rgb(180, 60, 200)); // behind = purple
    } else {
        draw_set_color(make_color_rgb(40, 160, 60));  // front  = green
    }
    scr_macro_body_rectangle(_tog_x, _row2, _tog_x + _tog_w, _row2 + _tog_h, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
   
    scr_node_macro_text_l(_tog_x + _tog_w * 0.5, _row2 -2, (_mode == 1) ? L("BEHIND BG") : L("IN FRONT"));
    draw_set_halign(fa_left);

}