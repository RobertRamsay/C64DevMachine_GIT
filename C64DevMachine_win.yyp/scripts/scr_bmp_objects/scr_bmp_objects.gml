/// ====================================================================
/// BMP OBJECTS — software sprites: masked bitmap objects drawn into a
/// bitmap by the game's own blitter (Saboteur, Exploding Fist style).
///
/// The asset's BUFFER is the C64 payload, byte for byte, exactly as it
/// sits in memory (pointer tables, masks and graphics, in whatever order
/// the game uses). meta.objects[] describes where each object lives:
///     { name, w, h, gfx_ptr, mask_ptr }
///       w, h      size in char cells (8x8)
///       gfx_ptr   absolute C64 address of the object's graphics
///       mask_ptr  absolute address of its mask (-1 = no mask)
/// Pointers that fall outside the buffer are kept but not editable.
///
/// Layout flags (shared by every object in the asset):
///     col_major   1 = cells stored column by column (top to bottom),
///                 0 = row by row (left to right)
///     bottom_up   1 = the 8 bytes of a cell are stored bottom row first
///     mask_and    1 = mask bit 1 keeps the background (AND mask),
///                 0 = mask bit 1 marks the object's solid pixels
///
/// Editing changes bytes in place, so the game's tables stay valid. The
/// editor shows a sheet of every object plus a zoomed view of one, in
/// three layers: GFX, MASK and COMPOSITE (what the game draws).
/// ====================================================================

function scr_bmpobj_create(_asset) {
    _asset.meta = {
        objects   : [],
        col_major : 1,
        bottom_up : 1,
        mask_and  : 1,
        ink       : 1,
        paper     : 11,
        sel       : 0,
        layer     : 2,      // 0 = GFX, 1 = MASK, 2 = COMPOSITE
        zoom      : 12,
        list_scroll : 0,
        stroke_val  : -1    // bit value being painted during a drag
    };
}

/// Keys that are the asset; the rest is editor state.
function scr_bmpobj_save_meta(_asset) {
    var _m = _asset.meta;
    return {
        objects   : _m.objects,
        col_major : _m.col_major,
        bottom_up : _m.bottom_up,
        mask_and  : _m.mask_and,
        ink       : _m.ink,
        paper     : _m.paper,
        sel       : _m.sel,
        layer     : _m.layer,
        zoom      : _m.zoom
    };
}

function scr_bmpobj_restore(_asset, _saved) {
    scr_bmpobj_create(_asset);
    if (!is_struct(_saved)) return;
    var _m = _asset.meta;
    var _keys = ["objects", "col_major", "bottom_up", "mask_and", "ink", "paper", "sel", "layer", "zoom"];
    for (var _k = 0; _k < array_length(_keys); _k++) {
        if (variable_struct_exists(_saved, _keys[_k])) {
            variable_struct_set(_m, _keys[_k], variable_struct_get(_saved, _keys[_k]));
        }
    }
}

/// Buffer offset of the byte holding pixel (_px,_py) of an object whose
/// data starts at absolute address _ptr. Returns -1 when not in the buffer.
function scr_bmpobj_byte_off(_asset, _o, _ptr, _px, _py) {
    var _m  = _asset.meta;
    var _cx = _px div 8;
    var _cy = _py div 8;
    var _r  = _py mod 8;
    var _cell = 0;
    if (_m.col_major == 1) {
        _cell = _cx * _o.h + _cy;
    } else {
        _cell = _cy * _o.w + _cx;
    }
    var _row = _r;
    if (_m.bottom_up == 1) {
        _row = 7 - _r;
    }
    var _off = (_ptr - real(_asset.address)) + _cell * 8 + _row;
    if (_ptr < 0) return -1;
    if (!buffer_exists(_asset.buffer)) return -1;
    if (_off < 0 || _off >= buffer_get_size(_asset.buffer)) return -1;
    return _off;
}

/// 0/1 for one pixel of the gfx (_which = 0) or mask (_which = 1) plane.
/// Missing data reads as 0 for gfx and "keep background" for the mask.
function scr_bmpobj_get(_asset, _o, _which, _px, _py) {
    var _ptr = _o.gfx_ptr;
    if (_which == 1) {
        _ptr = _o.mask_ptr;
    }
    var _off = scr_bmpobj_byte_off(_asset, _o, _ptr, _px, _py);
    if (_off < 0) {
        if (_which == 1) {
            return _asset.meta.mask_and;
        }
        return 0;
    }
    var _b = buffer_peek(_asset.buffer, _off, buffer_u8);
    return (_b >> (7 - (_px mod 8))) & 1;
}

function scr_bmpobj_set(_asset, _o, _which, _px, _py, _v) {
    var _ptr = _o.gfx_ptr;
    if (_which == 1) {
        _ptr = _o.mask_ptr;
    }
    var _off = scr_bmpobj_byte_off(_asset, _o, _ptr, _px, _py);
    if (_off < 0) return false;
    var _bit = 1 << (7 - (_px mod 8));
    var _b = buffer_peek(_asset.buffer, _off, buffer_u8);
    if (_v == 1) {
        _b = _b | _bit;
    } else {
        _b = _b & (~_bit & 0xFF);
    }
    buffer_poke(_asset.buffer, _off, buffer_u8, _b);
    return true;
}

/// Is a pixel part of the object's solid shape (mask says "draw here")?
function scr_bmpobj_solid(_asset, _o, _px, _py) {
    var _mk = scr_bmpobj_get(_asset, _o, 1, _px, _py);
    if (_asset.meta.mask_and == 1) {
        return (_mk == 0);
    }
    return (_mk == 1);
}

/// Draw one object at (_x,_y) with pixel size _s. _layer as meta.layer.
function scr_bmpobj_draw_object(_asset, _o, _x, _y, _s, _layer) {
    var _m = _asset.meta;
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    var _ink   = scr_c64_pepto_colour(_m.ink);
    var _paper = scr_c64_pepto_colour(_m.paper);
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _col = -1;
            if (_layer == 0) {
                if (scr_bmpobj_get(_asset, _o, 0, _px, _py) == 1) {
                    _col = _ink;
                } else {
                    _col = c_black;
                }
            } else if (_layer == 1) {
                if (scr_bmpobj_solid(_asset, _o, _px, _py)) {
                    _col = make_color_rgb(200, 60, 200);
                } else {
                    _col = make_color_rgb(30, 30, 40);
                }
            } else {
                if (scr_bmpobj_solid(_asset, _o, _px, _py)) {
                    if (scr_bmpobj_get(_asset, _o, 0, _px, _py) == 1) {
                        _col = _ink;
                    } else {
                        _col = c_black;
                    }
                } else {
                    if (scr_bmpobj_get(_asset, _o, 0, _px, _py) == 1) {
                        _col = _ink;
                    } else {
                        _col = _paper;
                    }
                }
            }
            draw_set_color(_col);
            draw_rectangle(_x + _px * _s, _y + _py * _s, _x + (_px + 1) * _s - 1, _y + (_py + 1) * _s - 1, false);
        }
    }
}

/// Fill the mask from the graphics: every set gfx pixel and its eight
/// neighbours become solid (a 1-pixel black outline, the classic look).
function scr_bmpobj_auto_mask(_asset, _o) {
    var _m  = _asset.meta;
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    var _solid = array_create(_pw * _ph, 0);
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            if (scr_bmpobj_get(_asset, _o, 0, _px, _py) == 1) {
                for (var _dy = -1; _dy <= 1; _dy++) {
                    for (var _dx = -1; _dx <= 1; _dx++) {
                        var _nx = _px + _dx;
                        var _ny = _py + _dy;
                        if (_nx >= 0 && _ny >= 0 && _nx < _pw && _ny < _ph) {
                            _solid[_ny * _pw + _nx] = 1;
                        }
                    }
                }
            }
        }
    }
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _v = _solid[_py * _pw + _px];
            if (_m.mask_and == 1) {
                _v = 1 - _v;
            }
            scr_bmpobj_set(_asset, _o, 1, _px, _py, _v);
        }
    }
}

function scr_bmpobj_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    var _button = function(_x1, _y1, _w, _label, _on, _mx2, _my2) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + 24);
        var _bg = make_color_rgb(31, 38, 54);
        if (_hov) { _bg = make_color_rgb(53, 61, 82); }
        if (_on)  { _bg = make_color_rgb(38, 94, 111); }
        draw_set_color(_bg);
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + 24, false);
        draw_set_color(make_color_rgb(72, 83, 103));
        if (_on) { draw_set_color(c_aqua); }
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + 24, true);
        draw_set_color(c_white);
        draw_text_l(_x1 + 8, _y1 + 7, _label);
        return (_hov && mouse_check_button_pressed(mb_left));
    };
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _top = _cy + 8;
    var _bottom = _vy2 - 16;

    if (_n == 0) {
        draw_set_color(c_ltgray);
        draw_text_l(_vx1 + 20, _top, "NO OBJECTS. Objects are listed in the asset file (meta.objects: w, h, gfx_ptr, mask_ptr).");
        return;
    }
    _m.sel = clamp(_m.sel, 0, _n - 1);
    var _o = _m.objects[_m.sel];

    // ── LEFT: object list ──
    var _lx = _vx1 + 16;
    var _lw = 220;
    var _row_h = 18;
    var _rows = floor((_bottom - _top - 40) / _row_h);
    draw_set_color(make_color_rgb(23, 29, 42));
    draw_rectangle(_lx - 6, _top - 6, _lx + _lw + 6, _bottom, false);
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_lx, _top, "OBJECTS (" + string(_n) + ")   wheel = scroll");
    var _ly = _top + 20;
    if (point_in_rectangle(_mx, _my, _lx, _ly, _lx + _lw, _bottom)) {
        if (mouse_wheel_down()) { _m.list_scroll = min(_m.list_scroll + 3, max(0, _n - _rows)); }
        if (mouse_wheel_up())   { _m.list_scroll = max(_m.list_scroll - 3, 0); }
    }
    for (var _i = _m.list_scroll; _i < min(_n, _m.list_scroll + _rows); _i++) {
        var _oi = _m.objects[_i];
        var _y = _ly + (_i - _m.list_scroll) * _row_h;
        var _hov = point_in_rectangle(_mx, _my, _lx, _y, _lx + _lw, _y + _row_h - 2);
        if (_i == _m.sel) {
            draw_set_color(make_color_rgb(38, 94, 111));
            draw_rectangle(_lx, _y, _lx + _lw, _y + _row_h - 2, false);
        } else if (_hov) {
            draw_set_color(make_color_rgb(53, 61, 82));
            draw_rectangle(_lx, _y, _lx + _lw, _y + _row_h - 2, false);
        }
        draw_set_color(c_white);
        draw_text_l(_lx + 4, _y + 3, string(_i) + "  " + string(_oi.name) + "  " + string(_oi.w) + "x" + string(_oi.h));
        if (_hov && mouse_check_button_pressed(mb_left)) { _m.sel = _i; }
    }

    // ── RIGHT: layer buttons, zoomed object, sheet ──
    var _ex = _lx + _lw + 30;
    var _bx = _ex;
    var _names = ["GFX", "MASK", "COMPOSITE"];
    for (var _l = 0; _l < 3; _l++) {
        if (_button(_bx, _top, 110, _names[_l], _m.layer == _l, _mx, _my)) { _m.layer = _l; }
        _bx += 118;
    }
    if (_button(_bx, _top, 130, "AUTO MASK", false, _mx, _my)) {
        scr_bmpobj_auto_mask(_asset, _o);
        global.addresses_dirty = true;
    }
    _bx += 138;
    if (_button(_bx, _top, 80, "ZOOM " + string(_m.zoom), false, _mx, _my)) {
        _m.zoom = _m.zoom + 4;
        if (_m.zoom > 20) { _m.zoom = 4; }
    }
    _bx += 88;
    if (_button(_bx, _top, 90, "INK " + string(_m.ink), false, _mx, _my)) { _m.ink = (_m.ink + 1) mod 16; }
    _bx += 98;
    if (_button(_bx, _top, 100, "PAPER " + string(_m.paper), false, _mx, _my)) { _m.paper = (_m.paper + 1) mod 16; }

    var _gx = _ex;
    var _gy = _top + 40;
    var _s = _m.zoom;
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    scr_bmpobj_draw_object(_asset, _o, _gx, _gy, _s, _m.layer);
    // cell grid
    draw_set_color(make_color_rgb(90, 90, 120));
    for (var _c = 0; _c <= _o.w; _c++) { draw_line(_gx + _c * 8 * _s, _gy, _gx + _c * 8 * _s, _gy + _ph * _s); }
    for (var _r = 0; _r <= _o.h; _r++) { draw_line(_gx, _gy + _r * 8 * _s, _gx + _pw * _s, _gy + _r * 8 * _s); }

    var _info = "GFX $" + string_upper(decimal_to_hex(_o.gfx_ptr));
    if (_o.mask_ptr >= 0) { _info += "   MASK $" + string_upper(decimal_to_hex(_o.mask_ptr)); }
    if (scr_bmpobj_byte_off(_asset, _o, _o.gfx_ptr, 0, 0) < 0) { _info += "   (GFX OUTSIDE THIS ASSET - READ ONLY)"; }
    draw_set_color(c_ltgray);
    draw_text_l(_gx, _gy + _ph * _s + 8, _info + "   L-click set, R-click clear (GFX or MASK layer)");

    // paint
    if (_m.layer < 2 && point_in_rectangle(_mx, _my, _gx, _gy, _gx + _pw * _s - 1, _gy + _ph * _s - 1)) {
        var _px = floor((_mx - _gx) / _s);
        var _py = floor((_my - _gy) / _s);
        var _v = -1;
        if (mouse_check_button(mb_left))  { _v = 1; }
        if (mouse_check_button(mb_right)) { _v = 0; }
        if (_v >= 0) {
            // On the MASK layer L-click paints SOLID, whatever the polarity.
            var _bitv = _v;
            if (_m.layer == 1 && _m.mask_and == 1) { _bitv = 1 - _v; }
            if (scr_bmpobj_set(_asset, _o, _m.layer, _px, _py, _bitv)) {
                        global.addresses_dirty = true;
            }
        }
    }

    // sheet of every object (composite, scale 2), click to select
    var _sx = _gx + max(_pw * _s, 320) + 30;
    var _sy0 = _top + 40;
    var _cx2 = _sx;
    var _cy2 = _sy0;
    var _line_h = 0;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_sx, _top + 26, "SHEET - click an object");
    for (var _i = 0; _i < _n; _i++) {
        var _oi = _m.objects[_i];
        var _w2 = _oi.w * 16;
        var _h2 = _oi.h * 16;
        if (_cx2 + _w2 > _vx2 - 16) { _cx2 = _sx; _cy2 += _line_h + 6; _line_h = 0; }
        if (_cy2 + _h2 > _bottom) { break; }
        scr_bmpobj_draw_object(_asset, _oi, _cx2, _cy2, 2, 2);
        if (_i == _m.sel) {
            draw_set_color(c_aqua);
            draw_rectangle(_cx2 - 1, _cy2 - 1, _cx2 + _w2, _cy2 + _h2, true);
        }
        if (point_in_rectangle(_mx, _my, _cx2, _cy2, _cx2 + _w2, _cy2 + _h2) && mouse_check_button_pressed(mb_left)) { _m.sel = _i; }
        _cx2 += _w2 + 6;
        _line_h = max(_line_h, _h2);
    }
}
