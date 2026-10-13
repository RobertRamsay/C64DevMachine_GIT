/// Shared editor chrome. Native nine-slice corners stay six pixels at any size.
/// Geometry is supplied by the caller's hit test; drawing never moves a control.
function scr_editor_control(_x1, _y1, _x2, _y2, _hover, _selected = false, _enabled = true) {
    var _frame = !_enabled ? 3 : (_selected ? 2 : (_hover ? 1 : 0));
    if (global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2);
    draw_sprite_stretched(spr_editor_slate, _frame, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

function scr_editor_panel(_x1, _y1, _x2, _y2, _recessed = false) {
    if (_recessed && global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2);
    draw_sprite_stretched(spr_editor_slate, _recessed ? 5 : 4, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

/// Label inside a control rect, vertically centred on the glyphs. Uses the
/// current font and colour. _halign fa_center centres across the rect;
/// fa_left / fa_right inset by _pad. Alignment state is restored afterwards.
function scr_editor_label(_x1, _y1, _x2, _y2, _text, _halign = fa_center, _pad = 6) {
    if (global.ph_capture) scr_panel_help_capture_label(_x1, _y1, _x2, _y2, _text);
    var _old_h = draw_get_halign();
    var _old_v = draw_get_valign();
    var _tx = floor((_x1 + _x2) * 0.5);
    if (_halign == fa_left)  _tx = _x1 + _pad;
    if (_halign == fa_right) _tx = _x2 - _pad;
    draw_set_halign(_halign);
    draw_set_valign(fa_middle);
    draw_text_l(_tx, floor((_y1 + _y2) * 0.5) + 1, _text);
    draw_set_halign(_old_h);
    draw_set_valign(_old_v);
}

/// C64 colour swatch: a rounded white tile (spr_editor_swatch frame 0,
/// nine-sliced so the corners stay round at any size) tinted with the
/// colour. No button frame around it. The colour is inset 2px so the
/// footprint (and the caller's hit test) stays the given rect; that margin
/// holds a rounded ring (frame 1) when hovered (grey) or selected (white).
function scr_editor_swatch(_x1, _y1, _x2, _y2, _col, _hover = false, _selected = false, _inset = 2) {
    if (global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2);
    scr_editor_colour_tile(_x1 + _inset, _y1 + _inset, _x2 - _inset, _y2 - _inset, _col);
    if (_selected || _hover) {
        scr_editor_colour_ring(_x1, _y1, _x2, _y2, _selected ? c_white : make_color_rgb(151, 170, 192));
    }
}

/// Rounded colour tile filling the rect (x2/y2 exclusive). Rects under 8px
/// either way are too small for the rounded corners and stay flat.
function scr_editor_colour_tile(_x1, _y1, _x2, _y2, _col, _alpha = 1) {
    var _w = _x2 - _x1;
    var _h = _y2 - _y1;
    if (_w < 8 || _h < 8) {
        var _old_col = draw_get_color();
        var _old_a   = draw_get_alpha();
        draw_set_color(_col);
        draw_set_alpha(_alpha);
        draw_rectangle(_x1, _y1, _x2 - 1, _y2 - 1, false);
        draw_set_color(_old_col);
        draw_set_alpha(_old_a);
        return;
    }
    draw_sprite_stretched_ext(spr_editor_swatch, 0, _x1, _y1, _w, _h, _col, _alpha);
}

/// Rounded 2px ring around a colour tile: hover (grey) / chosen (white).
function scr_editor_colour_ring(_x1, _y1, _x2, _y2, _col) {
    var _w = _x2 - _x1;
    var _h = _y2 - _y1;
    if (_w < 8 || _h < 8) {
        var _old_col = draw_get_color();
        draw_set_color(_col);
        draw_rectangle(_x1, _y1, _x2 - 1, _y2 - 1, true);
        draw_set_color(_old_col);
        return;
    }
    draw_sprite_stretched_ext(spr_editor_swatch, 1, _x1, _y1, _w, _h, _col, 1);
}

/// Decorative slots do not capture input or allocate an asset.
function scr_editor_empty_slot(_x1, _y1, _x2, _y2) {
    scr_editor_panel(_x1, _y1, _x2, _y2, true);
    var _old_col = draw_get_color();
    draw_set_color(make_color_rgb(72, 89, 109));
    var _cx = floor((_x1 + _x2) * 0.5);
    var _cy = floor((_y1 + _y2) * 0.5);
    draw_line(_cx - 3, _cy, _cx + 4, _cy);
    draw_line(_cx, _cy - 3, _cx, _cy + 4);
    draw_set_color(_old_col);
}
