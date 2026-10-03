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
        // POSES: how the game assembles parts into a figure. Each entry is
        // an array of part indices drawn top to bottom, left-aligned
        // (Saboteur: torso + legs, read from its pose table at $6F59).
        // Display only - the game's pose table lives in its own code.
        poses     : [],
        sheet_mode : 1,     // 0 = PARTS sheet, 1 = POSES sheet
        layer     : 2,      // 0 = GFX, 1 = MASK, 2 = COMPOSITE
        zoom      : 12,
        list_scroll : 0,
        stroke_val  : -1,   // bit value being painted during a drag

        // ── RENDER CACHE (editor only, never saved) ──
        // One 1:1 surface per object per layer, built from the buffer with a
        // single buffer_set_surface and drawn scaled. Rebuilt only when an
        // object is edited (cache_dirty[i]) or ink/paper change (cache_key).
        cache_surf  : [[], [], []],   // [layer][object] surface id, -1 = none
        cache_dirty : [],             // per object: true = rebuild all layers
        cache_key   : ""              // ink/paper/flags the cache was built with
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
        poses     : _m.poses,
        sheet_mode : _m.sheet_mode,
        layer     : _m.layer,
        zoom      : _m.zoom
    };
}

function scr_bmpobj_restore(_asset, _saved) {
    scr_bmpobj_create(_asset);
    if (!is_struct(_saved)) return;
    var _m = _asset.meta;
    var _keys = ["objects", "col_major", "bottom_up", "mask_and", "ink", "paper", "sel", "poses", "sheet_mode", "layer", "zoom"];
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

/// Colour of one pixel for a layer (0 GFX, 1 MASK, 2 COMPOSITE). -1 = transparent.
function scr_bmpobj_pixel_colour(_asset, _o, _layer, _px, _py, _ink, _paper) {
    var _g = scr_bmpobj_get(_asset, _o, 0, _px, _py);
    if (_layer == 0) {
        if (_g == 1) return _ink;
        return c_black;
    }
    var _solid = scr_bmpobj_solid(_asset, _o, _px, _py);
    if (_layer == 1) {
        if (_solid) return make_color_rgb(200, 60, 200);
        return make_color_rgb(30, 30, 40);
    }
    if (_g == 1) return _ink;
    if (_solid) return c_black;
    return _paper;
}

/// Mark one object (or all, _i = -1) for a cache rebuild.
function scr_bmpobj_cache_dirty(_asset, _i) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    if (array_length(_m.cache_dirty) != _n) {
        _m.cache_dirty = array_create(_n, true);
        return;
    }
    if (_i < 0) {
        for (var _k = 0; _k < _n; _k++) { _m.cache_dirty[_k] = true; }
    } else if (_i < _n) {
        _m.cache_dirty[_i] = true;
    }
}

/// Free every cached surface (asset closed / deleted).
function scr_bmpobj_cache_free(_asset) {
    var _m = _asset.meta;
    for (var _l = 0; _l < 3; _l++) {
        var _row = _m.cache_surf[_l];
        for (var _k = 0; _k < array_length(_row); _k++) {
            if (_row[_k] != -1 && surface_exists(_row[_k])) { surface_free(_row[_k]); }
            _row[_k] = -1;
        }
    }
}

/// Surface holding object _i at 1:1 for _layer, rebuilt only if needed.
function scr_bmpobj_surface(_asset, _i, _layer) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    var _key = string(_m.ink) + "/" + string(_m.paper) + "/" + string(_m.col_major) + string(_m.bottom_up) + string(_m.mask_and);
    if (_key != _m.cache_key || array_length(_m.cache_dirty) != _n) {
        _m.cache_key = _key;
        _m.cache_dirty = array_create(_n, true);
    }
    for (var _l = 0; _l < 3; _l++) {
        while (array_length(_m.cache_surf[_l]) < _n) { array_push(_m.cache_surf[_l], -1); }
    }
    if (_m.cache_dirty[_i]) {
        // edited: drop all three layers of this object
        for (var _l = 0; _l < 3; _l++) {
            var _old = _m.cache_surf[_l][_i];
            if (_old != -1 && surface_exists(_old)) { surface_free(_old); }
            _m.cache_surf[_l][_i] = -1;
        }
        _m.cache_dirty[_i] = false;
    }
    var _surf = _m.cache_surf[_layer][_i];
    if (_surf != -1 && surface_exists(_surf)) return _surf;

    var _o  = _m.objects[_i];
    var _pw = max(1, _o.w * 8);
    var _ph = max(1, _o.h * 8);
    var _ink   = scr_c64_pepto_colour(_m.ink);
    var _paper = scr_c64_pepto_colour(_m.paper);
    var _buf = buffer_create(_pw * _ph * 4, buffer_fixed, 1);
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _c = scr_bmpobj_pixel_colour(_asset, _o, _layer, _px, _py, _ink, _paper);
            var _off = (_py * _pw + _px) * 4;
            buffer_poke(_buf, _off,     buffer_u8, colour_get_red(_c));
            buffer_poke(_buf, _off + 1, buffer_u8, colour_get_green(_c));
            buffer_poke(_buf, _off + 2, buffer_u8, colour_get_blue(_c));
            buffer_poke(_buf, _off + 3, buffer_u8, 255);
        }
    }
    _surf = surface_create(_pw, _ph);
    buffer_set_surface(_buf, _surf, 0);
    buffer_delete(_buf);
    _m.cache_surf[_layer][_i] = _surf;
    return _surf;
}

/// Draw object _i at (_x,_y), pixel size _s, from the cache.
function scr_bmpobj_draw_object(_asset, _i, _x, _y, _s, _layer) {
    var _surf = scr_bmpobj_surface(_asset, _i, _layer);
    draw_surface_ext(_surf, _x, _y, _s, _s, 0, c_white, 1);
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
        scr_bmpobj_cache_dirty(_asset, _m.sel);
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
    scr_bmpobj_draw_object(_asset, _m.sel, _gx, _gy, _s, _m.layer);
    // cell grid
    draw_set_color(make_color_rgb(90, 90, 120));
    for (var _c = 0; _c <= _o.w; _c++) { draw_line(_gx + _c * 8 * _s, _gy, _gx + _c * 8 * _s, _gy + _ph * _s); }
    for (var _r = 0; _r <= _o.h; _r++) { draw_line(_gx, _gy + _r * 8 * _s, _gx + _pw * _s, _gy + _r * 8 * _s); }

    var _info = "GFX $" + string_upper(decimal_to_hex(_o.gfx_ptr));
    if (_o.mask_ptr >= 0) { _info += "   MASK $" + string_upper(decimal_to_hex(_o.mask_ptr)); }
    if (scr_bmpobj_byte_off(_asset, _o, _o.gfx_ptr, 0, 0) < 0) { _info += "   (GFX OUTSIDE THIS ASSET - READ ONLY)"; }
    var _used_in = "";
    for (var _pi = 0; _pi < array_length(_m.poses); _pi++) {
        var _pp = _m.poses[_pi];
        for (var _pk = 0; _pk < array_length(_pp); _pk++) {
            if (_pp[_pk] == _m.sel) { _used_in += " " + string(_pi); break; }
        }
    }
    if (_used_in != "") {
        draw_set_color(c_orange);
        draw_text_l(_gx, _gy + _ph * _s + 24, "PART OF POSES:" + _used_in + "   (editing it changes all of them)");
    }
    draw_set_color(c_ltgray);
    draw_text_l(_gx, _gy + _ph * _s + 8, _info + "   EDIT: L = ink/solid   R = clear/transparent   SHIFT+R (COMPOSITE) = black");

    // paint - every layer is editable:
    //   GFX        L = ink pixel        R = clear pixel
    //   MASK       L = solid            R = transparent (background shows)
    //   COMPOSITE  L = ink (solid)      R = transparent    SHIFT+R = black (solid)
    if (point_in_rectangle(_mx, _my, _gx, _gy, _gx + _pw * _s - 1, _gy + _ph * _s - 1)) {
        var _px = floor((_mx - _gx) / _s);
        var _py = floor((_my - _gy) / _s);
        var _lb = mouse_check_button(mb_left);
        var _rb = mouse_check_button(mb_right);
        var _changed = false;
        var _solid_bit = 1;
        if (_m.mask_and == 1) { _solid_bit = 0; }
        if (_lb || _rb) {
            var _g_old = scr_bmpobj_get(_asset, _o, 0, _px, _py);
            var _k_old = scr_bmpobj_get(_asset, _o, 1, _px, _py);
            var _g_new = _g_old;
            var _k_new = _k_old;
            if (_m.layer == 0) {
                if (_lb) { _g_new = 1; } else { _g_new = 0; }
            } else if (_m.layer == 1) {
                if (_lb) { _k_new = _solid_bit; } else { _k_new = 1 - _solid_bit; }
            } else {
                if (_lb) {
                    _g_new = 1; _k_new = _solid_bit;
                } else if (keyboard_check(vk_shift)) {
                    _g_new = 0; _k_new = _solid_bit;
                } else {
                    _g_new = 0; _k_new = 1 - _solid_bit;
                }
            }
            if (_g_new != _g_old) { _changed = scr_bmpobj_set(_asset, _o, 0, _px, _py, _g_new) || _changed; }
            if (_k_new != _k_old) { _changed = scr_bmpobj_set(_asset, _o, 1, _px, _py, _k_new) || _changed; }
        }
        if (_changed) {
            scr_bmpobj_cache_dirty(_asset, _m.sel);
            global.addresses_dirty = true;
        }
        // cursor cell outline
        draw_set_color(c_yellow);
        draw_rectangle(_gx + _px * _s, _gy + _py * _s, _gx + (_px + 1) * _s - 1, _gy + (_py + 1) * _s - 1, true);
    }

    // sheet: every PART, or every POSE (parts stacked as the game draws them)
    var _sx = _gx + max(_pw * _s, 320) + 30;
    var _sy0 = _top + 40;
    if (_button(_sx, _top, 90, "PARTS", _m.sheet_mode == 0, _mx, _my)) { _m.sheet_mode = 0; }
    if (array_length(_m.poses) > 0) {
        if (_button(_sx + 98, _top, 90, "POSES", _m.sheet_mode == 1, _mx, _my)) { _m.sheet_mode = 1; }
    }
    var _cx2 = _sx;
    var _cy2 = _sy0;
    var _line_h = 0;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_sx + 200, _top + 7, "click a part to edit it");
    if (_m.sheet_mode == 1 && array_length(_m.poses) > 0) {
        for (var _pi = 0; _pi < array_length(_m.poses); _pi++) {
            var _pp = _m.poses[_pi];
            var _pw2 = 0;
            var _ph2 = 0;
            for (var _pk = 0; _pk < array_length(_pp); _pk++) {
                var _part = _pp[_pk];
                if (_part < 0 || _part >= _n) continue;
                _pw2 = max(_pw2, _m.objects[_part].w * 16);
                _ph2 += _m.objects[_part].h * 16;
            }
            if (_cx2 + _pw2 > _vx2 - 16) { _cx2 = _sx; _cy2 += _line_h + 8; _line_h = 0; }
            if (_cy2 + _ph2 > _bottom) { break; }
            var _yy = _cy2;
            for (var _pk = 0; _pk < array_length(_pp); _pk++) {
                var _part = _pp[_pk];
                if (_part < 0 || _part >= _n) continue;
                var _po = _m.objects[_part];
                scr_bmpobj_draw_object(_asset, _part, _cx2, _yy, 2, 2);
                if (_part == _m.sel) {
                    draw_set_color(c_aqua);
                    draw_rectangle(_cx2 - 1, _yy - 1, _cx2 + _po.w * 16, _yy + _po.h * 16, true);
                }
                if (point_in_rectangle(_mx, _my, _cx2, _yy, _cx2 + _po.w * 16, _yy + _po.h * 16 - 1) && mouse_check_button_pressed(mb_left)) { _m.sel = _part; }
                _yy += _po.h * 16;
            }
            _cx2 += _pw2 + 8;
            _line_h = max(_line_h, _ph2);
        }
    } else {
        for (var _i = 0; _i < _n; _i++) {
            var _oi = _m.objects[_i];
            var _w2 = _oi.w * 16;
            var _h2 = _oi.h * 16;
            if (_cx2 + _w2 > _vx2 - 16) { _cx2 = _sx; _cy2 += _line_h + 6; _line_h = 0; }
            if (_cy2 + _h2 > _bottom) { break; }
            scr_bmpobj_draw_object(_asset, _i, _cx2, _cy2, 2, 2);
            if (_i == _m.sel) {
                draw_set_color(c_aqua);
                draw_rectangle(_cx2 - 1, _cy2 - 1, _cx2 + _w2, _cy2 + _h2, true);
            }
            if (point_in_rectangle(_mx, _my, _cx2, _cy2, _cx2 + _w2, _cy2 + _h2) && mouse_check_button_pressed(mb_left)) { _m.sel = _i; }
            _cx2 += _w2 + 6;
            _line_h = max(_line_h, _h2);
        }
    }
}
