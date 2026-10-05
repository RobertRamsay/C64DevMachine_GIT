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
        sheet_scroll : 0,   // editor only: sheet scroll in pixels
        // OBJECT COLOURS: each object may carry .colour = screen colour
        // byte (ink << 4 | paper) or -1 for AUTO (it takes the colour of
        // the cells it is drawn over, as Saboteur's props do). When
        // colour_addr > 0 a table of one byte per object is emitted there
        // for game code to apply; AUTO objects get colour_auto (the value
        // the game treats as "leave the cells alone" - Saboteur uses $00).
        colour_addr  : 0,
        colour_auto  : 255,
        layer     : 2,      // 0 = GFX, 1 = MASK, 2 = COMPOSITE
        zoom      : 12,
        list_scroll : 0,
        stroke_val  : -1,   // bit value being painted during a drag

        // ── RENDER CACHE (editor only, never saved) ──
        // One 1:1 surface per object per layer, built from the buffer with a
        // single buffer_set_surface and drawn scaled. Rebuilt only when an
        // object is edited (cache_dirty[i]) or ink/paper change (cache_key).
        cache_surf  : [[], [], [], [], [], []],   // [layer][object] surface id, -1 = none
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
        colour_addr : _m.colour_addr,
        colour_auto : _m.colour_auto,
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
    var _keys = ["objects", "col_major", "bottom_up", "mask_and", "ink", "paper", "sel", "colour_addr", "colour_auto", "poses", "sheet_mode", "layer", "zoom"];
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
    // -1 = "none": no graphics (all paper) / no mask (fully solid).
    // Games point these at memory that is always zero at run time.
    if (_ptr == -1) {
        if (_which == 1) {
            return 1 - _asset.meta.mask_and;
        }
        return 0;
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
    // layer 3 = composite with see-through background (map overlays)
    if (_layer == 3) return -1;
    return _paper;
}

/// Tint layers for the map overlay (drawn white, coloured by blending):
///   4 = ink pixels only, 5 = solid non-ink pixels only (they show the
///   cell's paper colour on the C64). Everything else is see-through.
function scr_bmpobj_tint_colour(_asset, _o, _layer, _px, _py) {
    var _g = scr_bmpobj_get(_asset, _o, 0, _px, _py);
    if (_layer == 4) {
        if (_g == 1) return c_white;
        return -1;
    }
    if (_g == 0 && scr_bmpobj_solid(_asset, _o, _px, _py)) return c_white;
    return -1;
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
    for (var _l = 0; _l < 6; _l++) {
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
    for (var _l = 0; _l < 6; _l++) {
        while (array_length(_m.cache_surf[_l]) < _n) { array_push(_m.cache_surf[_l], -1); }
    }
    if (_m.cache_dirty[_i]) {
        // edited: drop all three layers of this object
        for (var _l = 0; _l < 6; _l++) {
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
            var _c = -1;
            if (_layer >= 4) {
                _c = scr_bmpobj_tint_colour(_asset, _o, _layer, _px, _py);
            } else {
                _c = scr_bmpobj_pixel_colour(_asset, _o, _layer, _px, _py, _ink, _paper);
            }
            var _off = (_py * _pw + _px) * 4;
            if (_c == -1) {
                buffer_poke(_buf, _off,     buffer_u8, 0);
                buffer_poke(_buf, _off + 1, buffer_u8, 0);
                buffer_poke(_buf, _off + 2, buffer_u8, 0);
                buffer_poke(_buf, _off + 3, buffer_u8, 0);
            } else {
                buffer_poke(_buf, _off,     buffer_u8, colour_get_red(_c));
                buffer_poke(_buf, _off + 1, buffer_u8, colour_get_green(_c));
                buffer_poke(_buf, _off + 2, buffer_u8, colour_get_blue(_c));
                buffer_poke(_buf, _off + 3, buffer_u8, 255);
            }
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

/// Small UI helpers for the editor (immediate mode, return true on click).
function scr_bmpobj_ui_button(_x1, _y1, _w, _h, _label, _on, _mx, _my) {
    var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x1 + _w, _y1 + _h);
    var _bg = make_color_rgb(31, 38, 54);
    if (_hov) { _bg = make_color_rgb(53, 61, 82); }
    if (_on)  { _bg = make_color_rgb(38, 94, 111); }
    draw_set_color(_bg);
    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
    draw_set_color(make_color_rgb(72, 83, 103));
    if (_on) { draw_set_color(c_aqua); }
    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_x1 + _w / 2, _y1 + (_h div 2) - 4, _label);
    draw_set_halign(fa_left);
    return (_hov && mouse_check_button_pressed(mb_left));
}

function scr_bmpobj_ui_panel(_x1, _y1, _x2, _y2, _title) {
    draw_set_color(make_color_rgb(20, 25, 37));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(52, 62, 84));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_color(make_color_rgb(30, 37, 53));
    draw_rectangle(_x1 + 1, _y1 + 1, _x2 - 1, _y1 + 20, false);
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_x1 + 8, _y1 + 6, _title);
}

/// Colour picker row: label, < swatch >. Returns the new colour index.
function scr_bmpobj_ui_colour(_x, _y, _label, _col, _mx, _my) {
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_x, _y + 8, _label);
    var _bx = _x + 50;
    if (scr_bmpobj_ui_button(_bx, _y, 22, 24, "<", false, _mx, _my)) { _col = (_col + 15) mod 16; }
    draw_set_color(scr_c64_pepto_colour(_col));
    draw_rectangle(_bx + 28, _y, _bx + 64, _y + 24, false);
    draw_set_color(c_white);
    draw_rectangle(_bx + 28, _y, _bx + 64, _y + 24, true);
    if (scr_bmpobj_ui_button(_bx + 70, _y, 22, 24, ">", false, _mx, _my)) { _col = (_col + 1) mod 16; }
    return _col;
}

/// Editor entry point. Pixel art must stay crisp: texture filtering is
/// switched off for the whole editor and restored afterwards.
function scr_bmpobj_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _old_filter = gpu_get_texfilter();
    gpu_set_texfilter(false);
    scr_bmpobj_editor_body(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my);
    gpu_set_texfilter(_old_filter);
}

/// Layout
///   ┌ toolbar: LAYER [GFX][MASK][COMPOSITE]  [AUTO MASK]  ZOOM [-] n [+]  INK < >  PAPER < > ┐
///   ├ PARTS list ┬ EDIT canvas + info ───────┬ SHEET [PARTS][POSES]  (wheel scrolls) ──┤
///   └────────────┴───────────────────────────┴─────────────────────────────────────────┘
function scr_bmpobj_editor_body(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _pad = 12;
    var _top = _cy + 8;
    var _bottom = _vy2 - 12;
    var _left = _vx1 + _pad;
    var _right = _vx2 - _pad;

    if (_n == 0) {
        draw_set_color(c_ltgray);
        draw_text_l(_left, _top, "NO OBJECTS. The asset lists them in meta.objects (w, h, gfx_ptr, mask_ptr).");
        return;
    }
    _m.sel = clamp(_m.sel, 0, _n - 1);
    _m.layer = clamp(_m.layer, 0, 2);
    var _o = _m.objects[_m.sel];

    // ── TOOLBAR ──
    var _tb_h = 26;
    var _x = _left;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_x, _top + 9, "LAYER");
    _x += 52;
    var _lnames = ["GFX", "MASK", "COMPOSITE"];
    var _lw = [56, 62, 100];
    // only the three editor views get buttons (layers 3-5 are map-overlay surfaces)
    for (var _l = 0; _l < array_length(_lnames); _l++) {
        if (scr_bmpobj_ui_button(_x, _top, _lw[_l], _tb_h, _lnames[_l], _m.layer == _l, _mx, _my)) { _m.layer = _l; }
        _x += _lw[_l] + 4;
    }
    _x += 16;
    if (scr_bmpobj_ui_button(_x, _top, 100, _tb_h, "AUTO MASK", false, _mx, _my)) {
        scr_bmpobj_auto_mask(_asset, _o);
        scr_bmpobj_cache_dirty(_asset, _m.sel);
        global.addresses_dirty = true;
    }
    _x += 120;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_x, _top + 9, "ZOOM");
    _x += 44;
    if (scr_bmpobj_ui_button(_x, _top, 24, _tb_h, "-", false, _mx, _my)) { _m.zoom = max(2, _m.zoom - 2); }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_x + 44, _top + 9, string(_m.zoom) + "x");
    draw_set_halign(fa_left);
    if (scr_bmpobj_ui_button(_x + 64, _top, 24, _tb_h, "+", false, _mx, _my)) { _m.zoom = min(24, _m.zoom + 2); }
    _x += 108;
    var _ink = scr_bmpobj_ui_colour(_x, _top, "INK", _m.ink, _mx, _my);
    _x += 160;
    var _paper = scr_bmpobj_ui_colour(_x, _top, "PAPER", _m.paper, _mx, _my);
    _m.ink = _ink;
    _m.paper = _paper;

    // ── COLUMNS ──
    var _ptop = _top + _tb_h + 12;
    var _list_w = 210;
    var _lx1 = _left;
    var _lx2 = _left + _list_w;
    var _edit_w = clamp((_right - _lx2) * 0.45, 360, 620);
    var _ex1 = _lx2 + _pad;
    var _ex2 = _ex1 + _edit_w;
    var _sx1 = _ex2 + _pad;
    var _sx2 = _right;

    // ── PARTS LIST ──
    scr_bmpobj_ui_panel(_lx1, _ptop, _lx2, _bottom, "PARTS (" + string(_n) + ")");
    var _row_h = 18;
    var _ly = _ptop + 26;
    var _rows = max(1, floor((_bottom - _ly - 4) / _row_h));
    if (point_in_rectangle(_mx, _my, _lx1, _ly, _lx2, _bottom)) {
        if (mouse_wheel_down()) { _m.list_scroll = min(_m.list_scroll + 3, max(0, _n - _rows)); }
        if (mouse_wheel_up())   { _m.list_scroll = max(_m.list_scroll - 3, 0); }
    }
    _m.list_scroll = clamp(_m.list_scroll, 0, max(0, _n - _rows));
    for (var _i = _m.list_scroll; _i < min(_n, _m.list_scroll + _rows); _i++) {
        var _oi = _m.objects[_i];
        var _y = _ly + (_i - _m.list_scroll) * _row_h;
        var _hov = point_in_rectangle(_mx, _my, _lx1 + 2, _y, _lx2 - 2, _y + _row_h - 2);
        if (_i == _m.sel) {
            draw_set_color(make_color_rgb(38, 94, 111));
            draw_rectangle(_lx1 + 2, _y, _lx2 - 2, _y + _row_h - 2, false);
        } else if (_hov) {
            draw_set_color(make_color_rgb(42, 50, 70));
            draw_rectangle(_lx1 + 2, _y, _lx2 - 2, _y + _row_h - 2, false);
        }
        draw_set_color(c_white);
        draw_text_l(_lx1 + 8, _y + 4, string(_oi.name));
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_set_halign(fa_right);
        draw_text_l(_lx2 - 8, _y + 4, string(_oi.w) + "x" + string(_oi.h));
        draw_set_halign(fa_left);
        if (_hov && mouse_check_button_pressed(mb_left)) { _m.sel = _i; }
    }

    // ── EDIT PANEL ──
    scr_bmpobj_ui_panel(_ex1, _ptop, _ex2, _bottom, "EDIT  " + string(_o.name) + "   " + string(_o.w) + "x" + string(_o.h) + " cells");
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    var _info_h = 96;
    var _avail_w = _edit_w - 24;
    var _avail_h = (_bottom - _ptop) - 26 - _info_h - 16;
    var _s = _m.zoom;
    // shrink to fit, never past 2x
    while (_s > 2 && (_pw * _s > _avail_w || _ph * _s > _avail_h)) { _s -= 1; }
    var _gx = _ex1 + floor((_edit_w - _pw * _s) / 2);
    var _gy = _ptop + 30 + max(0, floor((_avail_h - _ph * _s) / 2));
    draw_set_color(make_color_rgb(10, 12, 18));
    draw_rectangle(_gx - 4, _gy - 4, _gx + _pw * _s + 3, _gy + _ph * _s + 3, false);
    scr_bmpobj_draw_object(_asset, _m.sel, _gx, _gy, _s, _m.layer);
    // pixel grid (only when it is readable) and cell grid
    if (_s >= 8) {
        draw_set_color(make_color_rgb(40, 40, 55));
        draw_set_alpha(0.5);
        for (var _c = 1; _c < _pw; _c++) { draw_line(_gx + _c * _s, _gy, _gx + _c * _s, _gy + _ph * _s); }
        for (var _r = 1; _r < _ph; _r++) { draw_line(_gx, _gy + _r * _s, _gx + _pw * _s, _gy + _r * _s); }
        draw_set_alpha(1);
    }
    draw_set_color(make_color_rgb(110, 110, 150));
    for (var _c = 0; _c <= _o.w; _c++) { draw_line(_gx + _c * 8 * _s, _gy, _gx + _c * 8 * _s, _gy + _ph * _s); }
    for (var _r = 0; _r <= _o.h; _r++) { draw_line(_gx, _gy + _r * 8 * _s, _gx + _pw * _s, _gy + _r * 8 * _s); }

    // paint - every layer is editable:
    //   GFX        L = ink pixel        R = clear pixel
    //   MASK       L = solid            R = transparent (background shows)
    //   COMPOSITE  L = ink (solid)      R = transparent    SHIFT+R = black (solid)
    // Read-only only when neither plane lives in this asset (a mask-only
    // prop with gfx = none can still have its mask edited).
    var _read_only = (scr_bmpobj_byte_off(_asset, _o, _o.gfx_ptr, 0, 0) < 0)
                  && (scr_bmpobj_byte_off(_asset, _o, _o.mask_ptr, 0, 0) < 0);
    if (!_read_only && point_in_rectangle(_mx, _my, _gx, _gy, _gx + _pw * _s - 1, _gy + _ph * _s - 1)) {
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
        draw_set_color(c_yellow);
        draw_rectangle(_gx + _px * _s, _gy + _py * _s, _gx + (_px + 1) * _s - 1, _gy + (_py + 1) * _s - 1, true);
    }

    // info box
    var _iy = _bottom - _info_h;
    draw_set_color(make_color_rgb(30, 37, 53));
    draw_rectangle(_ex1 + 8, _iy, _ex2 - 8, _bottom - 8, false);
    var _info = "GFX $" + string_upper(decimal_to_hex(_o.gfx_ptr));
    if (_o.mask_ptr >= 0) { _info += "    MASK $" + string_upper(decimal_to_hex(_o.mask_ptr)); }
    draw_set_color(c_white);
    draw_text_l(_ex1 + 16, _iy + 8, _info);
    if (_read_only) {
        draw_set_color(c_orange);
        draw_text_l(_ex1 + 16, _iy + 24, "GRAPHICS ARE OUTSIDE THIS ASSET - READ ONLY");
    } else {
        var _help = "L = ink   R = clear";
        if (_m.layer == 1) { _help = "L = solid   R = transparent"; }
        if (_m.layer == 2) { _help = "L = ink   R = transparent   SHIFT+R = black"; }
        draw_set_color(make_color_rgb(154, 175, 198));
        draw_text_l(_ex1 + 16, _iy + 24, _lnames[_m.layer] + ":  " + _help);
    }
    var _used_in = "";
    for (var _pi = 0; _pi < array_length(_m.poses); _pi++) {
        var _pp = _m.poses[_pi];
        for (var _pk = 0; _pk < array_length(_pp); _pk++) {
            if (_pp[_pk] == _m.sel) { _used_in += " " + string(_pi); break; }
        }
    }
    // OBJECT COLOUR: AUTO (takes the cells' colours) or a fixed ink/paper.
    // Emitted as one byte per object at colour_addr when that is set.
    var _ccol = scr_bmpobj_get_colour(_asset, _m.sel);
    var _ccx = _ex2 - 190;
    if (scr_bmpobj_ui_button(_ccx, _iy + 6, 80, 20, "AUTO COL", _ccol < 0, _mx, _my)) {
        if (_ccol < 0) {
            scr_bmpobj_set_colour(_asset, _m.sel, (1 << 4) | 0);
        } else {
            scr_bmpobj_set_colour(_asset, _m.sel, -1);
        }
        scr_bmpobj_cache_dirty(_asset, _m.sel);
    }
    if (_ccol >= 0) {
        var _cink = scr_bmpobj_ui_colour(_ccx, _iy + 32, "INK", (_ccol >> 4) & 0x0F, _mx, _my);
        var _cpap = scr_bmpobj_ui_colour(_ccx, _iy + 60, "PAPER", _ccol & 0x0F, _mx, _my);
        var _cnew = (_cink << 4) | _cpap;
        if (_cnew != _ccol) {
            scr_bmpobj_set_colour(_asset, _m.sel, _cnew);
        }
    }
    if (_used_in != "") {
        draw_set_color(c_orange);
        draw_text_l(_ex1 + 16, _iy + 44, "USED IN POSES:" + _used_in);
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_ex1 + 16, _iy + 60, "editing this part changes every pose listed");
    }

    // ── SHEET PANEL ──
    scr_bmpobj_ui_panel(_sx1, _ptop, _sx2, _bottom, "SHEET  - click a part to edit it, wheel scrolls");
    var _have_poses = (array_length(_m.poses) > 0);
    if (scr_bmpobj_ui_button(_sx2 - 190, _ptop + 2, 88, 17, "PARTS", _m.sheet_mode == 0, _mx, _my)) { _m.sheet_mode = 0; _m.sheet_scroll = 0; }
    if (_have_poses) {
        if (scr_bmpobj_ui_button(_sx2 - 96, _ptop + 2, 88, 17, "POSES", _m.sheet_mode == 1, _mx, _my)) { _m.sheet_mode = 1; _m.sheet_scroll = 0; }
    } else {
        _m.sheet_mode = 0;
    }
    var _st = _ptop + 28;
    var _sb = _bottom - 6;
    if (point_in_rectangle(_mx, _my, _sx1, _st, _sx2, _sb)) {
        if (mouse_wheel_down()) { _m.sheet_scroll += 48; }
        if (mouse_wheel_up())   { _m.sheet_scroll = max(0, _m.sheet_scroll - 48); }
    }
    var _ss = 2;
    var _gap = 10;
    var _cx2 = _sx1 + 10;
    var _cy2 = _st - _m.sheet_scroll;
    var _line_h = 0;
    var _content_bottom = _cy2;
    // a scissor keeps scrolled items inside the panel
    // GUI -> window pixels, same scaling the inline editors use
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(floor((_sx1 + 1) * _sx_sc), floor(_st * _sy_sc), ceil((_sx2 - _sx1 - 2) * _sx_sc), ceil((_sb - _st) * _sy_sc));
    var _count = _n;
    if (_m.sheet_mode == 1) { _count = array_length(_m.poses); }
    for (var _k = 0; _k < _count; _k++) {
        // the parts making up this item, top to bottom
        var _parts = [_k];
        if (_m.sheet_mode == 1) { _parts = _m.poses[_k]; }
        var _iw = 0;
        var _ih = 0;
        for (var _pk = 0; _pk < array_length(_parts); _pk++) {
            var _part = _parts[_pk];
            if (_part < 0 || _part >= _n) continue;
            _iw = max(_iw, _m.objects[_part].w * 8 * _ss);
            _ih += _m.objects[_part].h * 8 * _ss;
        }
        if (_cx2 + _iw > _sx2 - 10) { _cx2 = _sx1 + 10; _cy2 += _line_h + _gap + 12; _line_h = 0; }
        // label above each item
        draw_set_color(make_color_rgb(110, 120, 140));
        draw_text_l(_cx2, _cy2, string(_k));
        var _yy = _cy2 + 12;
        for (var _pk = 0; _pk < array_length(_parts); _pk++) {
            var _part = _parts[_pk];
            if (_part < 0 || _part >= _n) continue;
            var _po = _m.objects[_part];
            var _w2 = _po.w * 8 * _ss;
            var _h2 = _po.h * 8 * _ss;
            if (_yy + _h2 >= _st && _yy <= _sb) {
                scr_bmpobj_draw_object(_asset, _part, _cx2, _yy, _ss, 2);
                if (_part == _m.sel) {
                    draw_set_color(c_aqua);
                    draw_rectangle(_cx2 - 1, _yy - 1, _cx2 + _w2, _yy + _h2, true);
                }
                if (point_in_rectangle(_mx, _my, _cx2, max(_yy, _st), _cx2 + _w2, min(_yy + _h2 - 1, _sb))
                &&  mouse_check_button_pressed(mb_left)) {
                    _m.sel = _part;
                }
            }
            _yy += _h2;
        }
        _cx2 += _iw + _gap;
        _line_h = max(_line_h, _ih);
        _content_bottom = _cy2 + 12 + _line_h;
    }
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    // clamp scroll to the content
    var _overflow = (_content_bottom + _m.sheet_scroll) - _sb;
    _m.sheet_scroll = clamp(_m.sheet_scroll, 0, max(0, _overflow));
}


/// One byte per object for the game: the object's colour, or colour_auto
/// for AUTO objects.
function scr_bmpobj_colour_table(_asset) {
    var _out = [];
    var _auto = real(_asset.meta.colour_auto) & 0xFF;
    var _objs = _asset.meta.objects;
    for (var _i = 0; _i < array_length(_objs); _i++) {
        var _c = -1;
        if (variable_struct_exists(_objs[_i], "colour")) {
            _c = real(_objs[_i].colour);
        }
        if (_c < 0) {
            array_push(_out, _auto);
        } else {
            array_push(_out, _c & 0xFF);
        }
    }
    return _out;
}

/// Colour byte of object _i (-1 = AUTO). Objects from older files have
/// no .colour yet; they are given one here (AUTO).
function scr_bmpobj_get_colour(_asset, _i) {
    var _o = _asset.meta.objects[_i];
    if (!variable_struct_exists(_o, "colour")) {
        _o.colour = -1;
    }
    return real(_o.colour);
}

function scr_bmpobj_set_colour(_asset, _i, _c) {
    // a colour equal to the game's AUTO value would read back as AUTO
    if (_c >= 0 && _c == (real(_asset.meta.colour_auto) & 0xFF)) {
        _c = -1;
    }
    _asset.meta.objects[_i].colour = _c;
    global.addresses_dirty = true;
}

/// Draw object _i like the C64 would over a coloured map: each 8x8 cell
/// gets ink and paper from _colour_fn(cell_x, cell_y) -> colour byte, or
/// from the object's own colour when it has one.
/// _x/_y = top-left on screen, _s = screen pixels per C64 pixel.
function scr_bmpobj_draw_tinted(_asset, _i, _x, _y, _s, _cell_colour_fn) {
    var _o = _asset.meta.objects[_i];
    var _own = scr_bmpobj_get_colour(_asset, _i);
    var _sink = scr_bmpobj_surface(_asset, _i, 4);
    var _spap = scr_bmpobj_surface(_asset, _i, 5);
    for (var _cy = 0; _cy < _o.h; _cy++) {
        for (var _cx = 0; _cx < _o.w; _cx++) {
            var _cb = _own;
            if (_cb < 0) {
                _cb = _cell_colour_fn(_cx, _cy);
            }
            var _dx = _x + _cx * 8 * _s;
            var _dy = _y + _cy * 8 * _s;
            draw_surface_part_ext(_spap, _cx * 8, _cy * 8, 8, 8, _dx, _dy, _s, _s, scr_c64_pepto_colour(_cb & 0x0F), draw_get_alpha());
            draw_surface_part_ext(_sink, _cx * 8, _cy * 8, 8, 8, _dx, _dy, _s, _s, scr_c64_pepto_colour((_cb >> 4) & 0x0F), draw_get_alpha());
        }
    }
}
