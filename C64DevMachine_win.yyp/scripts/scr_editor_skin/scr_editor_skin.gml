/// Shared editor chrome. Native nine-slice corners stay six pixels at any size.
/// Geometry is supplied by the caller's hit test; drawing never moves a control.
function scr_editor_control(_x1, _y1, _x2, _y2, _hover, _selected = false, _enabled = true) {
    var _frame = !_enabled ? 3 : (_selected ? 2 : (_hover ? 1 : 0));
    draw_sprite_stretched(spr_editor_slate, _frame, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

function scr_editor_panel(_x1, _y1, _x2, _y2, _recessed = false) {
    draw_sprite_stretched(spr_editor_slate, _recessed ? 5 : 4, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1));
}

/// Decorative slots do not capture input or allocate an asset.
function scr_editor_empty_slot(_x1, _y1, _x2, _y2) {
    scr_editor_panel(_x1, _y1, _x2, _y2, true);
    var _old_col = draw_get_color();
    draw_set_color(make_color_rgb(72, 89, 109));
    var _cx = (_x1 + _x2) * 0.5;
    var _cy = (_y1 + _y2) * 0.5;
    draw_line(_cx - 3, _cy, _cx + 3, _cy);
    draw_line(_cx, _cy - 3, _cx, _cy + 3);
    draw_set_color(_old_col);
}
