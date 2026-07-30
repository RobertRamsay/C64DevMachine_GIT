/// @desc Modal info dialog rendering + input

var _gw = display_get_gui_width();
var _gh = display_get_gui_height();

// ── Dim backdrop ──
draw_set_alpha(0.7);
draw_set_colour(c_black);
draw_rectangle(0, 0, _gw, _gh, false);
draw_set_alpha(1.0);

// ── Box geometry ──
var _bx = (_gw - box_w) * 0.5;
var _by = (_gh - box_h) * 0.5;

// Drop shadow
draw_set_alpha(0.5);
draw_set_colour(c_black);
draw_rectangle(_bx + 6, _by + 6, _bx + box_w + 6, _by + box_h + 6, false);
draw_set_alpha(1.0);

// Box fill
draw_set_colour(make_colour_rgb(40, 40, 50));
draw_rectangle(_bx, _by, _bx + box_w, _by + box_h, false);

// Box border (pulsed)
var _border_pulse = 0.5 + 0.5 * sin(pulse);
var _br = lerp(120, 200, _border_pulse);
draw_set_colour(make_colour_rgb(80, _br, 200));
draw_rectangle(_bx, _by, _bx + box_w, _by + box_h, true);
draw_rectangle(_bx + 1, _by + 1, _bx + box_w - 1, _by + box_h - 1, true);

// ── Message text ──
draw_set_font(fnt_c64_code);
draw_set_colour(c_white);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);

var _msg_x = _bx + box_w * 0.5;
var _msg_y = _by + 60;

draw_text_ext(_msg_x, _msg_y, message, 24, box_w - 60);

// ── OK button (single, centred) ──
var _btn_y  = _by + box_h - btn_h - 22;
var _btn_x  = _bx + (box_w - btn_w) * 0.5;

var _mx = global.gui_mouse_x;
var _my = global.gui_mouse_y;

hover_ok = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + btn_w, _btn_y + btn_h);

if (hover_ok) {
    draw_set_colour(make_colour_rgb(80, 130, 180));
} else {
    draw_set_colour(make_colour_rgb(50, 80, 120));
}
draw_rectangle(_btn_x, _btn_y, _btn_x + btn_w, _btn_y + btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_x, _btn_y, _btn_x + btn_w, _btn_y + btn_h, true);
draw_text(_btn_x + btn_w * 0.5, _btn_y + btn_h * 0.5, "OK");

draw_set_halign(fa_left);
draw_set_valign(fa_top);

// ── Input (only when armed) ──
if (input_armed) {
    if (mouse_check_button_pressed(mb_left)) {
        if (hover_ok) {
            dismissed = true;
        }
    }
    if (keyboard_check_pressed(vk_enter) ||
        keyboard_check_pressed(vk_space) ||
        keyboard_check_pressed(vk_escape)) {
        dismissed = true;
    }
}