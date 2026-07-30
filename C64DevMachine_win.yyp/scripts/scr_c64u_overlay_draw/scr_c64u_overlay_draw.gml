/// @function scr_c64u_overlay_draw()
/// @description Draws the IP entry overlay on GUI layer with Cancel/Save buttons.
function scr_c64u_overlay_draw()
{
    if (global.c64u_overlay_active == false)
    {
        return;
    }

    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();

    // --- Dim backdrop ---
    draw_set_alpha(0.75);
    draw_set_colour(c_black);
    draw_rectangle(0, 0, _gw, _gh, false);
    draw_set_alpha(1.0);

    // --- Panel ---
    var _pw = 580;
    var _ph = 260;
    var _px = (_gw - _pw) * 0.5;
    var _py = (_gh - _ph) * 0.5;

    draw_set_colour(make_colour_rgb(40, 40, 90));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);

    draw_set_colour(make_colour_rgb(180, 180, 255));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);

    // --- Title ---
    draw_set_font(fnt_C64_Angled_big);
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    draw_set_colour(c_white);
    draw_text(_px + _pw * 0.5, _py + 14, "C64 ULTIMATE - ENTER IP");

    // --- Input box ---
    var _bx1 = _px + 40;
    var _by1 = _py + 70;
    var _bx2 = _px + _pw - 40;
    var _by2 = _by1 + 44;

    draw_set_colour(c_black);
    draw_rectangle(_bx1, _by1, _bx2, _by2, false);
    draw_set_colour(make_colour_rgb(120, 120, 200));
    draw_rectangle(_bx1, _by1, _bx2, _by2, true);

    draw_set_colour(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_middle);
    var _display = global.c64u_overlay_text;
    if ((current_time div 500) mod 2 == 0)
    {
        _display += "_";
    }
    draw_text(_bx1 + 14, (_by1 + _by2) * 0.5, _display);

    // --- Status / error line ---
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    if (global.c64u_overlay_error != "")
    {
        // Reddish if it contains "Invalid" or "fail" or "Could not", yellow-ish otherwise (e.g. "Pinging...")
        var _err = global.c64u_overlay_error;
        var _is_bad = false;
        if (string_pos("Invalid", _err) > 0)   { _is_bad = true; }
        if (string_pos("fail", _err) > 0)      { _is_bad = true; }
        if (string_pos("Could not", _err) > 0) { _is_bad = true; }
        if (string_pos("unreachable", _err) > 0) { _is_bad = true; }
        if (string_pos("error", _err) > 0)     { _is_bad = true; }

        if (_is_bad == true)
        {
            draw_set_colour(make_colour_rgb(255, 120, 120));
        }
        else
        {
            draw_set_colour(make_colour_rgb(255, 230, 140));
        }
        draw_text(_px + _pw * 0.5, _by2 + 14, _err);
    }

    // --- Buttons: Cancel (left) and Save & Test (right) ---
    var _btn_w = 200;
    var _btn_h = 44;
    var _btn_y = _py + _ph - _btn_h - 18;

    var _cancel_x1 = _px + 30;
    var _cancel_y1 = _btn_y;
    var _cancel_x2 = _cancel_x1 + _btn_w;
    var _cancel_y2 = _cancel_y1 + _btn_h;

    var _save_x1 = _px + _pw - 30 - _btn_w;
    var _save_y1 = _btn_y;
    var _save_x2 = _save_x1 + _btn_w;
    var _save_y2 = _save_y1 + _btn_h;

    // Store hit-rects for step handler
    global.c64u_cancel_x1 = _cancel_x1;
    global.c64u_cancel_y1 = _cancel_y1;
    global.c64u_cancel_x2 = _cancel_x2;
    global.c64u_cancel_y2 = _cancel_y2;
    global.c64u_save_x1   = _save_x1;
    global.c64u_save_y1   = _save_y1;
    global.c64u_save_x2   = _save_x2;
    global.c64u_save_y2   = _save_y2;

    // Cancel button
    var _cancel_hover = (global.gui_mouse_x >= _cancel_x1 && global.gui_mouse_x <= _cancel_x2
                     && global.gui_mouse_y >= _cancel_y1 && global.gui_mouse_y <= _cancel_y2);
    if (_cancel_hover == true)
    {
        draw_set_colour(make_colour_rgb(120, 60, 60));
    }
    else
    {
        draw_set_colour(make_colour_rgb(80, 40, 40));
    }
    draw_rectangle(_cancel_x1, _cancel_y1, _cancel_x2, _cancel_y2, false);
    draw_set_colour(make_colour_rgb(200, 120, 120));
    draw_rectangle(_cancel_x1, _cancel_y1, _cancel_x2, _cancel_y2, true);
    draw_set_colour(c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text((_cancel_x1 + _cancel_x2) * 0.5, (_cancel_y1 + _cancel_y2) * 0.5, "CANCEL (ESC)");

    // Save button
    var _save_hover = (global.gui_mouse_x >= _save_x1 && global.gui_mouse_x <= _save_x2
                   && global.gui_mouse_y >= _save_y1 && global.gui_mouse_y <= _save_y2);
    if (_save_hover == true)
    {
        draw_set_colour(make_colour_rgb(60, 120, 60));
    }
    else
    {
        draw_set_colour(make_colour_rgb(40, 80, 40));
    }
    draw_rectangle(_save_x1, _save_y1, _save_x2, _save_y2, false);
    draw_set_colour(make_colour_rgb(120, 200, 120));
    draw_rectangle(_save_x1, _save_y1, _save_x2, _save_y2, true);
    draw_set_colour(c_white);
    draw_text((_save_x1 + _save_x2) * 0.5, (_save_y1 + _save_y2) * 0.5, "TEST & SAVE");

    // --- Reset draw state ---
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1.0);
}