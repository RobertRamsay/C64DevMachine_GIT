/// @desc Modal dialog rendering + input

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

// Box border (pulsed for the "active dialog" feel)
var _border_pulse = 0.5 + 0.5 * sin(pulse);
var _br = lerp(180, 255, _border_pulse);
draw_set_colour(make_colour_rgb(_br, _br, 80));
draw_rectangle(_bx, _by, _bx + box_w, _by + box_h, true);
draw_rectangle(_bx + 1, _by + 1, _bx + box_w - 1, _by + box_h - 1, true);

// ── Message text ──
// Use your existing font - swap fnt_c64_code for whichever font you prefer
draw_set_font(fnt_c64_code);
draw_set_colour(c_white);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);

var _msg_x = _bx + box_w * 0.5;
var _msg_y = _by + 70;

// Multi-line draw with manual wrap. Splits on \n already in the message.
draw_text_ext(_msg_x, _msg_y, message, 24, box_w - 60);

// ── Buttons ──
var _btn_y    = _by + box_h - btn_h - 28;
var _total_w  = (btn_w * 2) + btn_gap;
var _btn_yx   = _bx + (box_w - _total_w) * 0.5;            // YES x
var _btn_nx   = _btn_yx + btn_w + btn_gap;                 // NO  x

var _mx = global.gui_mouse_x;
var _my = global.gui_mouse_y;

hover_yes = point_in_rectangle(_mx, _my, _btn_yx, _btn_y, _btn_yx + btn_w, _btn_y + btn_h);
hover_no  = point_in_rectangle(_mx, _my, _btn_nx, _btn_y, _btn_nx + btn_w, _btn_y + btn_h);

// YES button
if (hover_yes) {
    draw_set_colour(make_colour_rgb(80, 160, 80));
} else {
    draw_set_colour(make_colour_rgb(50, 100, 50));
}
draw_rectangle(_btn_yx, _btn_y, _btn_yx + btn_w, _btn_y + btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_yx, _btn_y, _btn_yx + btn_w, _btn_y + btn_h, true);
draw_text(_btn_yx + btn_w * 0.5, _btn_y + btn_h * 0.5, "YES");

// NO button
if (hover_no) {
    draw_set_colour(make_colour_rgb(160, 80, 80));
} else {
    draw_set_colour(make_colour_rgb(100, 50, 50));
}
draw_rectangle(_btn_nx, _btn_y, _btn_nx + btn_w, _btn_y + btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_nx, _btn_y, _btn_nx + btn_w, _btn_y + btn_h, true);
draw_text(_btn_nx + btn_w * 0.5, _btn_y + btn_h * 0.5, "NO");

// Reset draw state
draw_set_halign(fa_left);
draw_set_valign(fa_top);

// ── Input handling (only after input is armed) ──
if (input_armed) {
    // Mouse click
    if (mouse_check_button_pressed(mb_left)) {
        if (hover_yes) {
            result = 1;
        } else if (hover_no) {
            result = 0;
        }
    }

    // Keyboard shortcuts: Enter/Y = Yes, Esc/N = No
    if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(ord("Y"))) {
        result = 1;
    }
    if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(ord("N"))) {
        result = 0;
    }
}