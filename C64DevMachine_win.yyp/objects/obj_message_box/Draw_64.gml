/// @desc Modal info dialog rendering + input

var _gw = display_get_gui_width();
var _gh = display_get_gui_height();

// ── Dim backdrop ──
draw_set_alpha(0.7);
draw_set_colour(c_black);
draw_rectangle(0, 0, _gw, _gh, false);
draw_set_alpha(1.0);

// ── Box geometry ──
// The box grows to fit its message. At the fixed 200px height a five-line
// message ran straight under the OK button and hid its last line.
draw_set_font(fnt_c64_code);

var _txt_w   = box_w - 60;
var _txt_h   = string_height_ext(message, 24, _txt_w);

// OK button is its label plus 4px of padding on every side.
var _ok_w    = string_width("OK")  + 8;
var _ok_h    = string_height("OK") + 8;

var _pad_top = 30;   // above the text
var _pad_gap = 20;   // between text and button
var _pad_bot = 22;   // below the button

var _bh = max(box_h, _pad_top + _txt_h + _pad_gap + _ok_h + _pad_bot);

var _bx = (_gw - box_w) * 0.5;
var _by = (_gh - _bh)   * 0.5;

// Drop shadow
draw_set_alpha(0.5);
draw_set_colour(c_black);
draw_rectangle(_bx + 6, _by + 6, _bx + box_w + 6, _by + _bh + 6, false);
draw_set_alpha(1.0);

// Box fill
draw_set_colour(make_colour_rgb(40, 40, 50));
draw_rectangle(_bx, _by, _bx + box_w, _by + _bh, false);

// Box border (pulsed)
var _border_pulse = 0.5 + 0.5 * sin(pulse);
var _br = lerp(120, 200, _border_pulse);
draw_set_colour(make_colour_rgb(80, _br, 200));
draw_rectangle(_bx, _by, _bx + box_w, _by + _bh, true);
draw_rectangle(_bx + 1, _by + 1, _bx + box_w - 1, _by + _bh - 1, true);

// ── Message text ──
// Top-anchored rather than centred, so the button sits below the REAL bottom
// of the text instead of a guessed offset.
draw_set_colour(c_white);
draw_set_halign(fa_center);
draw_set_valign(fa_top);

var _msg_x = _bx + box_w * 0.5;
var _msg_y = _by + _pad_top;

draw_text_ext(_msg_x, _msg_y, message, 24, _txt_w);

// ── OK button (single, centred, sized to its label) ──
var _btn_w  = _ok_w;
var _btn_h  = _ok_h;
var _btn_y  = _msg_y + _txt_h + _pad_gap;
var _btn_x  = _bx + (box_w - _btn_w) * 0.5;

var _mx = global.gui_mouse_x;
var _my = global.gui_mouse_y;

hover_ok = point_in_rectangle(_mx, _my, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);

if (hover_ok) {
    draw_set_colour(make_colour_rgb(80, 130, 180));
} else {
    draw_set_colour(make_colour_rgb(50, 80, 120));
}
draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, true);
draw_set_valign(fa_middle);
draw_text(_btn_x + _btn_w * 0.5, _btn_y + _btn_h * 0.5, "OK");

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