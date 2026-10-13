/// Shared editor chrome. Native nine-slice corners stay six pixels at any size.
/// Geometry is supplied by the caller's hit test; drawing never moves a control.
/// All chrome is multiplied by global.ui_tint, the current theme's tint.

// THEME TINT: a near-white colour carrying the hue of the active theme's
// artwork (its opcode palette page and top bar). Multiplying the slate by it
// shifts the hue a little without changing how light the UI reads.
global.ui_tint     = c_white;
global.ui_tint_key = "";

/// @desc Recompute global.ui_tint when the theme changes. Cheap when it has
///       not (one string compare); call once per frame from a draw event.
function scr_ui_tint_update() {
    if (!instance_exists(obj_workspace_manager)) return;
    var _wm  = obj_workspace_manager;
    var _pn  = max(1, sprite_get_number(spr_palette_page));
    var _mn  = max(1, sprite_get_number(spr_menu_bar));
    var _pf  = clamp(_wm.paletteStyle, 0, _pn - 1);
    var _mf  = clamp((_wm.uiChromeStyle == 0) ? _wm.paletteStyle : _mn - 1, 0, _mn - 1);
    var _key = string(_pf) + ":" + string(_mf);
    if (_key == global.ui_tint_key) return;
    global.ui_tint_key = _key;

    // Average colour of both pieces of art, by shrinking them onto a small
    // surface (filtered) and reading it back.
    var _w = 32;
    var _h = 16;
    var _s = surface_create(_w, _h * 2);
    var _old_filter = gpu_get_texfilter();
    surface_set_target(_s);
    draw_clear_alpha(c_black, 0);
    gpu_set_texfilter(true);
    draw_sprite_stretched(spr_palette_page, _pf, 0, 0, _w, _h);
    draw_sprite_stretched(spr_menu_bar, _mf, 0, _h, _w, _h);
    gpu_set_texfilter(_old_filter);
    surface_reset_target();
    var _buf = buffer_create(_w * _h * 2 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _s, 0);
    surface_free(_s);
    var _r = 0, _g = 0, _b = 0, _n = 0;
    for (var _i = 0; _i < _w * _h * 2; _i++) {
        var _a = buffer_peek(_buf, _i * 4 + 3, buffer_u8);
        if (_a < 64) continue;
        _r += buffer_peek(_buf, _i * 4,     buffer_u8);   // RGBA, as the bitmap code reads surfaces
        _g += buffer_peek(_buf, _i * 4 + 1, buffer_u8);
        _b += buffer_peek(_buf, _i * 4 + 2, buffer_u8);
        _n++;
    }
    buffer_delete(_buf);
    if (_n == 0) { global.ui_tint = c_white; return; }
    var _avg = make_color_rgb(_r / _n, _g / _n, _b / _n);
    // Hue of the art, at a fraction of its saturation: a hint, never a wash.
    var _sat = min(color_get_saturation(_avg) * 0.65, 90);
    global.ui_tint = (_sat < 6) ? c_white : make_color_hsv(color_get_hue(_avg), _sat, 255);
}

/// @desc A colour multiplied by the theme tint (for chrome drawn as plain
///       rectangles, e.g. asset panel rows).
function scr_ui_tinted(_col) {
    var _t = global.ui_tint;
    return make_color_rgb(color_get_red(_col)   * color_get_red(_t)   / 255,
                          color_get_green(_col) * color_get_green(_t) / 255,
                          color_get_blue(_col)  * color_get_blue(_t)  / 255);
}

function scr_editor_control(_x1, _y1, _x2, _y2, _hover, _selected = false, _enabled = true) {
    var _frame = !_enabled ? 3 : (_selected ? 2 : (_hover ? 1 : 0));
    if (global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2);
    draw_sprite_stretched_ext(spr_editor_slate, _frame, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1), global.ui_tint, draw_get_alpha());
}

function scr_editor_panel(_x1, _y1, _x2, _y2, _recessed = false) {
    if (_recessed && global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2);
    draw_sprite_stretched_ext(spr_editor_slate, _recessed ? 5 : 4, _x1, _y1, max(1, _x2 - _x1), max(1, _y2 - _y1), global.ui_tint, draw_get_alpha());
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
    if (global.ph_capture) scr_panel_help_capture(_x1, _y1, _x2, _y2, "swatch");
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
