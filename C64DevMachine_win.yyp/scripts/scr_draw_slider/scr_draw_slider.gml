/// @function scr_draw_slider(_mx, _my, _x, _y, _w, _label, _val, _min, _max, _pressed, _asset, _id, _default_val)
/// @desc Draws a labelled horizontal slider. Returns the new value.
///       _asset/_id give each slider an exclusive drag lock (_asset.meta.active_slider_id):
///       once a slider claims the drag on press, dragging the mouse across a
///       NEIGHBOURING slider's track while still holding the button no longer
///       makes that neighbour react too — only the original owner responds,
///       until the button is released.
///       Right-clicking the track resets it to _default_val (or the midpoint
///       of _min/_max if no default is given).
function scr_draw_slider(_mx, _my, _x, _y, _w, _label, _val, _min, _max, _pressed, _asset, _id, _default_val = undefined) {
    if (!variable_struct_exists(_asset.meta, "active_slider_id")) _asset.meta.active_slider_id = "";
    
    var _h       = 12;
    var _track_y = _y + 6;
    var _t       = clamp((_val - _min) / (_max - _min), 0, 1);
    var _knob_x  = floor(_x + _t * _w);
    var _in_track = point_in_rectangle(_mx, _my, _x - 6, _y - 2, _x + _w + 6, _y + _h + 2);
    
    var _is_owner = (_asset.meta.active_slider_id == _id);
    
    // Claim the drag lock only on a fresh press while nothing else owns it.
    if (_in_track && _pressed && _asset.meta.active_slider_id == "") {
        _asset.meta.active_slider_id = _id;
        _is_owner = true;
    }
    
    // Track
    scr_editor_panel(_x, _track_y - 4, _x + _w, _track_y + 4, true);
    if (_knob_x > _x + 2) {
        draw_set_color(make_color_rgb(50, 90, 150));
        draw_rectangle(_x + 2, _track_y - 2, _knob_x, _track_y + 2, false);
    }
    // Knob
    scr_editor_control(_knob_x - 6, _y, _knob_x + 6, _y + _h, _in_track, _is_owner);
    // Label
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    var _disp = string(floor(_val * 10) / 10);
    draw_text_l(_x, _y + _h + 2, _label + ": " + _disp);
    // Drag — only the owning slider responds, regardless of where the mouse is now
    if (_is_owner && _pressed) {
        _val = _min + clamp((_mx - _x) / _w, 0, 1) * (_max - _min);
    }
    // Release the lock as soon as the button is no longer held
    if (_is_owner && !_pressed) {
        _asset.meta.active_slider_id = "";
    }
    // Right-click reset — only when nothing is mid-drag, so a right-click
    // can't interrupt or fight an in-progress left-drag on another slider.
    if (_in_track && mouse_check_button_pressed(mb_right) && _asset.meta.active_slider_id == "") {
        _val = (_default_val != undefined) ? _default_val : ((_min + _max) / 2);
    }
    return _val;
}