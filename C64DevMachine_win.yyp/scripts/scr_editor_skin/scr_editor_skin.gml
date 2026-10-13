/// Shared editor chrome. Native nine-slice corners stay six pixels at any size.
/// Geometry is supplied by the caller's hit test; drawing never moves a control.
function scr_editor_control(_x1, _y1, _x2, _y2, _hover, _selected = false, _enabled = true) {
    var _frame = !_enabled ? 3 : (_selected ? 2 : (_hover ? 1 : 0));
    draw_sprite_stretched(spr_editor_slate, _frame, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

function scr_editor_panel(_x1, _y1, _x2, _y2, _recessed = false) {
    draw_sprite_stretched(spr_editor_slate, _recessed ? 5 : 4, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

/// Label inside a control rect, vertically centred on the glyphs. Uses the
/// current font and colour. _halign fa_center centres across the rect;
/// fa_left / fa_right inset by _pad. Alignment state is restored afterwards.
function scr_editor_label(_x1, _y1, _x2, _y2, _text, _halign = fa_center, _pad = 6) {
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

/// C64 colour swatch set in a small recessed well. The colour is inset 2px
/// so the footprint (and the caller's hit test) stays the given rect.
/// Hovered / selected swatches use the control frames (same rounded shape),
/// so no extra outline rectangle is needed around them.
function scr_editor_swatch(_x1, _y1, _x2, _y2, _col, _hover = false, _selected = false) {
    if (_selected || _hover) {
        scr_editor_control(_x1, _y1, _x2, _y2, _hover, _selected);
    } else {
        scr_editor_panel(_x1, _y1, _x2, _y2, true);
    }
    var _old_col = draw_get_color();
    draw_set_color(_col);
    draw_rectangle(_x1 + 2, _y1 + 2, _x2 - 2, _y2 - 2, false);
    draw_set_color(_old_col);
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
