/// @desc Modal W x H dialog rendering + input

var _gw = display_get_gui_width();
var _gh = display_get_gui_height();

// -- Dim backdrop --
draw_set_alpha(0.7);
draw_set_colour(c_black);
draw_rectangle(0, 0, _gw, _gh, false);
draw_set_alpha(1.0);

// -- Box geometry --
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
var _br = lerp(180, 255, _border_pulse);
draw_set_colour(make_colour_rgb(_br, _br, 80));
draw_rectangle(_bx, _by, _bx + box_w, _by + box_h, true);
draw_rectangle(_bx + 1, _by + 1, _bx + box_w - 1, _by + box_h - 1, true);

// -- Title --
draw_set_font(fnt_c64_code);
draw_set_colour(c_white);
draw_set_halign(fa_center);
draw_set_valign(fa_middle);
draw_text(_bx + box_w * 0.5, _by + 44, "SLICE INTO ROOMS (W x H)");

// -- Field geometry --
var _flds_total = (fld_w * 2) + fld_gap;
var _fld_wx     = _bx + (box_w - _flds_total) * 0.5;   // W field x
var _fld_hx     = _fld_wx + fld_w + fld_gap;           // H field x
var _fld_y      = _by + 96;

var _mx = global.gui_mouse_x;
var _my = global.gui_mouse_y;

hover_fld_w = point_in_rectangle(_mx, _my, _fld_wx, _fld_y, _fld_wx + fld_w, _fld_y + fld_h);
hover_fld_h = point_in_rectangle(_mx, _my, _fld_hx, _fld_y, _fld_hx + fld_w, _fld_y + fld_h);

var _caret = "";
if (caret_timer < 30) _caret = "_";

// W field
if (active_field == 0) {
    draw_set_colour(make_colour_rgb(30, 70, 45));
} else {
    draw_set_colour(make_colour_rgb(20, 35, 25));
}
draw_rectangle(_fld_wx, _fld_y, _fld_wx + fld_w, _fld_y + fld_h, false);
draw_set_colour(c_white);
draw_rectangle(_fld_wx, _fld_y, _fld_wx + fld_w, _fld_y + fld_h, true);
if (active_field == 0) {
    draw_set_colour(c_lime);
    draw_text(_fld_wx + fld_w * 0.5, _fld_y + fld_h * 0.5, field_w + _caret);
} else {
    draw_set_colour(c_aqua);
    draw_text(_fld_wx + fld_w * 0.5, _fld_y + fld_h * 0.5, field_w);
}

// "x" separator
draw_set_colour(c_white);
draw_text((_fld_wx + fld_w + _fld_hx) * 0.5, _fld_y + fld_h * 0.5, "x");

// H field
if (active_field == 1) {
    draw_set_colour(make_colour_rgb(30, 70, 45));
} else {
    draw_set_colour(make_colour_rgb(20, 35, 25));
}
draw_rectangle(_fld_hx, _fld_y, _fld_hx + fld_w, _fld_y + fld_h, false);
draw_set_colour(c_white);
draw_rectangle(_fld_hx, _fld_y, _fld_hx + fld_w, _fld_y + fld_h, true);
if (active_field == 1) {
    draw_set_colour(c_lime);
    draw_text(_fld_hx + fld_w * 0.5, _fld_y + fld_h * 0.5, field_h + _caret);
} else {
    draw_set_colour(c_aqua);
    draw_text(_fld_hx + fld_w * 0.5, _fld_y + fld_h * 0.5, field_h);
}

// -- Buttons --
var _btn_y   = _by + box_h - btn_h - 28;
var _total_w = (btn_w * 2) + btn_gap;
var _btn_sx  = _bx + (box_w - _total_w) * 0.5;         // SLICE x
var _btn_cx  = _btn_sx + btn_w + btn_gap;              // CANCEL x

hover_slice  = point_in_rectangle(_mx, _my, _btn_sx, _btn_y, _btn_sx + btn_w, _btn_y + btn_h);
hover_cancel = point_in_rectangle(_mx, _my, _btn_cx, _btn_y, _btn_cx + btn_w, _btn_y + btn_h);

// SLICE button
if (hover_slice) {
    draw_set_colour(make_colour_rgb(80, 160, 80));
} else {
    draw_set_colour(make_colour_rgb(50, 100, 50));
}
draw_rectangle(_btn_sx, _btn_y, _btn_sx + btn_w, _btn_y + btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_sx, _btn_y, _btn_sx + btn_w, _btn_y + btn_h, true);
draw_text(_btn_sx + btn_w * 0.5, _btn_y + btn_h * 0.5, "SLICE");

// CANCEL button
if (hover_cancel) {
    draw_set_colour(make_colour_rgb(160, 80, 80));
} else {
    draw_set_colour(make_colour_rgb(100, 50, 50));
}
draw_rectangle(_btn_cx, _btn_y, _btn_cx + btn_w, _btn_y + btn_h, false);
draw_set_colour(c_white);
draw_rectangle(_btn_cx, _btn_y, _btn_cx + btn_w, _btn_y + btn_h, true);
draw_text(_btn_cx + btn_w * 0.5, _btn_y + btn_h * 0.5, "CANCEL");

// Reset draw state
draw_set_halign(fa_left);
draw_set_valign(fa_top);

// -- Input handling (only after input is armed) --
if (input_armed) {

    // Field selection on mouse release
    if (mouse_check_button_released(mb_left)) {
        if (hover_fld_w) {
            active_field = 0;
        } else if (hover_fld_h) {
            active_field = 1;
        }
    }

    // Tab switches field
    if (keyboard_check_pressed(vk_tab)) {
        if (active_field == 0) {
            active_field = 1;
        } else {
            active_field = 0;
        }
    }

    // Digit entry / backspace on the active field
    var _cur = field_w;
    if (active_field == 1) _cur = field_h;

    var _dk = -1;
    if (keyboard_check_pressed(ord("0")) || keyboard_check_pressed(vk_numpad0)) _dk = 0;
    if (keyboard_check_pressed(ord("1")) || keyboard_check_pressed(vk_numpad1)) _dk = 1;
    if (keyboard_check_pressed(ord("2")) || keyboard_check_pressed(vk_numpad2)) _dk = 2;
    if (keyboard_check_pressed(ord("3")) || keyboard_check_pressed(vk_numpad3)) _dk = 3;
    if (keyboard_check_pressed(ord("4")) || keyboard_check_pressed(vk_numpad4)) _dk = 4;
    if (keyboard_check_pressed(ord("5")) || keyboard_check_pressed(vk_numpad5)) _dk = 5;
    if (keyboard_check_pressed(ord("6")) || keyboard_check_pressed(vk_numpad6)) _dk = 6;
    if (keyboard_check_pressed(ord("7")) || keyboard_check_pressed(vk_numpad7)) _dk = 7;
    if (keyboard_check_pressed(ord("8")) || keyboard_check_pressed(vk_numpad8)) _dk = 8;
    if (keyboard_check_pressed(ord("9")) || keyboard_check_pressed(vk_numpad9)) _dk = 9;

    if (_dk >= 0) {
        if (string_length(_cur) < 3) {
            _cur = _cur + string(_dk);
        }
    }

    if (keyboard_check_pressed(vk_backspace)) {
        if (string_length(_cur) > 0) {
            _cur = string_copy(_cur, 1, string_length(_cur) - 1);
        }
    }

    if (active_field == 0) {
        field_w = _cur;
    } else {
        field_h = _cur;
    }

    // Commit / cancel
    var _do_slice  = false;
    var _do_cancel = false;

    if (mouse_check_button_released(mb_left)) {
        if (hover_slice) {
            _do_slice = true;
        } else if (hover_cancel) {
            _do_cancel = true;
        }
    }
    if (keyboard_check_pressed(vk_enter)) {
        _do_slice = true;
    }
    if (keyboard_check_pressed(vk_escape)) {
        _do_cancel = true;
    }

    if (_do_slice || _do_cancel) {
        global.integer_box_open = false;
    }

    if (_do_slice) {
        var _rw = 0;
        var _rh = 0;
        if (string_length(field_w) > 0) _rw = real(field_w);
        if (string_length(field_h) > 0) _rh = real(field_h);
        global.integer_result = {
            w:         _rw,
            h:         _rh,
            action:    action,
            cancelled: false
        };
        instance_destroy();
    }

    if (_do_cancel) {
        global.integer_result = {
            w:         0,
            h:         0,
            action:    action,
            cancelled: true
        };
        instance_destroy();
    }
}