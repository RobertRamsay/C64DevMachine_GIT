/// ====================================================================
/// SPRITE MASK — foreground masking for sprites over a bitmap scene.
///
/// SPRITE_MASK asset: a 1-bit layer painted over a BITMAP (1 = foreground,
/// the sprite goes behind it) plus a per-cell DEPTH: the bitmap Y of the
/// object's front edge. A masked cell only hides the sprite while the
/// sprite's hotspot (feet) is ABOVE that line; 255 = always.
///
/// The layer is compiled exactly, cell by cell, with repeats removed:
///   +0     map    1000 bytes, cell index per char position (0 = no mask)
///   +1000  depth   256 bytes, depth per index
///   +1256  chars  8 bytes per index, 1 = sprite SHOWS (index 0 = all $FF)
/// Identical 8x8 shapes with the same depth share one index, so the blob
/// is 1256 + 8 * (unique + 1) bytes. The asset's buffer IS that blob, so
/// it can be linked into a LOAD_REU like any other asset.
///
/// MACRO_SPR_MASK node: ["macro_spr_mask", source, slots, hot_y, work, zp]
///   source = a ROOM_MAP (mask of whichever room is current, fetched by
///   MACRO_ROOMS into its MASK RAM) or a SPRITE_MASK (static, blob inline).
///   Each call builds a 21-line mask from the cells under the sprite and
///   copies the current frame of every listed slot, ANDed with it, into a
///   double-buffered work block, then points the slot at it. When nothing
///   under the sprite is masked, the original frame pointers are restored.
/// ====================================================================

function scr_sprmask_create(_asset) {
    _asset.meta = {
        ref_bmp     : "",
        mask        : array_create(8000, 0),
        cell_base   : array_create(1000, 255),
        tool        : "PAINT",
        brush       : 2,
        depth       : 255,
        pick_y      : false,
        pick_open   : false,
        pick_scroll : 0,
        undo        : [],
        stroke      : false,
        last_x      : -1,
        last_y      : -1,
        ov_surf     : -1,
        ov_dirty    : true,
        stat_unique : 0,
        stat_over   : 0,
        tone_sorted : false,
        mc_mode     : 0
    };
    scr_sprmask_flush(_asset);
}

/// Saveable form of the meta (mask + depths as base64, the rest plain).
function scr_sprmask_save_meta(_asset) {
    var _m  = _asset.meta;
    var _b1 = buffer_create(8000, buffer_fixed, 1);
    for (var _i = 0; _i < 8000; _i++) { buffer_poke(_b1, _i, buffer_u8, _m.mask[_i]); }
    var _b2 = buffer_create(1000, buffer_fixed, 1);
    for (var _i = 0; _i < 1000; _i++) { buffer_poke(_b2, _i, buffer_u8, _m.cell_base[_i]); }
    var _out = {
        ref_bmp    : _m.ref_bmp,
        mask_b64   : buffer_base64_encode(_b1, 0, 8000),
        depth_b64  : buffer_base64_encode(_b2, 0, 1000),
        tool       : _m.tool,
        brush      : _m.brush,
        depth      : _m.depth
    };
    buffer_delete(_b1);
    buffer_delete(_b2);
    return _out;
}

function scr_sprmask_restore(_asset, _saved) {
    scr_sprmask_create(_asset);
    var _m = _asset.meta;
    if (!is_struct(_saved)) return;
    if (variable_struct_exists(_saved, "ref_bmp")) { _m.ref_bmp = _saved.ref_bmp; }
    if (variable_struct_exists(_saved, "tool"))    { _m.tool    = _saved.tool; }
    if (variable_struct_exists(_saved, "brush"))   { _m.brush   = _saved.brush; }
    if (variable_struct_exists(_saved, "depth"))   { _m.depth   = _saved.depth; }
    if (variable_struct_exists(_saved, "mask_b64")) {
        var _b = buffer_base64_decode(_saved.mask_b64);
        if (buffer_exists(_b)) {
            var _n = min(8000, buffer_get_size(_b));
            for (var _i = 0; _i < _n; _i++) { _m.mask[_i] = buffer_peek(_b, _i, buffer_u8); }
            buffer_delete(_b);
        }
    }
    if (variable_struct_exists(_saved, "depth_b64")) {
        var _b2 = buffer_base64_decode(_saved.depth_b64);
        if (buffer_exists(_b2)) {
            var _n2 = min(1000, buffer_get_size(_b2));
            for (var _i = 0; _i < _n2; _i++) { _m.cell_base[_i] = buffer_peek(_b2, _i, buffer_u8); }
            buffer_delete(_b2);
        }
    }
    scr_sprmask_flush(_asset);
}

function scr_sprmask_find_asset(_name) {
    if (_name == "" || !instance_exists(obj_asset_manager)) return undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SPRITE_MASK" && _a.name == _name) return _a;
    }
    return undefined;
}

/// Compile the layer: returns { map, base, chars, unique, over }.
function scr_sprmask_compile(_asset) {
    var _m     = _asset.meta;
    var _map   = array_create(1000, 0);
    var _base  = array_create(256, 255);
    var _chars = [255, 255, 255, 255, 255, 255, 255, 255];
    var _seen  = ds_map_create();
    var _uniq  = 0;
    var _over  = 0;
    for (var _c = 0; _c < 1000; _c++) {
        var _any = false;
        for (var _r = 0; _r < 8; _r++) {
            if (_m.mask[_c * 8 + _r] != 0) { _any = true; break; }
        }
        if (!_any) continue;
        var _key = string(_m.cell_base[_c]);
        for (var _r = 0; _r < 8; _r++) { _key += "," + string(_m.mask[_c * 8 + _r]); }
        var _idx = ds_map_find_value(_seen, _key);
        if (is_undefined(_idx)) {
            if (_uniq >= 255) {
                _over += 1;
                continue;
            }
            _uniq += 1;
            _idx = _uniq;
            ds_map_add(_seen, _key, _idx);
            _base[_idx] = _m.cell_base[_c];
            for (var _r = 0; _r < 8; _r++) {
                array_push(_chars, (~_m.mask[_c * 8 + _r]) & 0xFF);   // 1 = sprite shows
            }
        }
        _map[_c] = _idx;
    }
    ds_map_destroy(_seen);
    return { map: _map, base: _base, chars: _chars, unique: _uniq, over: _over };
}

/// Rebuild the asset's buffer (the REU payload) from the painted layer.
function scr_sprmask_flush(_asset) {
    var _cm   = scr_sprmask_compile(_asset);
    var _size = 1256 + array_length(_cm.chars);
    if (buffer_exists(_asset.buffer)) { buffer_delete(_asset.buffer); }
    _asset.buffer = buffer_create(_size, buffer_fixed, 1);
    for (var _i = 0; _i < 1000; _i++) { buffer_poke(_asset.buffer, _i, buffer_u8, _cm.map[_i]); }
    for (var _i = 0; _i < 256; _i++)  { buffer_poke(_asset.buffer, 1000 + _i, buffer_u8, _cm.base[_i]); }
    for (var _i = 0; _i < array_length(_cm.chars); _i++) {
        buffer_poke(_asset.buffer, 1256 + _i, buffer_u8, _cm.chars[_i]);
    }
    _asset.meta.stat_unique = _cm.unique;
    _asset.meta.stat_over   = _cm.over;
    global.memory_bar_dirty = true;
}

/// C64 colour of the bitmap pixel at hires x,y (-1 if no bitmap).
function scr_sprmask_bmp_colour(_bmp, _x, _y, _hires) {
    if (is_undefined(_bmp) || !buffer_exists(_bmp.buffer) || buffer_get_size(_bmp.buffer) < 10003) return -1;
    var _buf  = _bmp.buffer;
    var _cell = (_y >> 3) * 40 + (_x >> 3);
    var _b    = buffer_peek(_buf, 2 + _cell * 8 + (_y & 7), buffer_u8);
    var _scr  = buffer_peek(_buf, 8002 + _cell, buffer_u8);
    if (_hires) {
        if (((_b >> (7 - (_x & 7))) & 1) == 1) { return _scr >> 4; }
        return _scr & 15;
    }
    var _pair = (_b >> (6 - 2 * ((_x & 7) >> 1))) & 3;
    if (_pair == 0) { return buffer_peek(_buf, 10002, buffer_u8) & 15; }
    if (_pair == 1) { return _scr >> 4; }
    if (_pair == 2) { return _scr & 15; }
    return buffer_peek(_buf, 9002 + _cell, buffer_u8) & 15;
}

/// Set (_on) or clear one hires pixel; stamps the current depth on set.
function scr_sprmask_set_px(_m, _x, _y, _on) {
    if (_x < 0 || _x > 319 || _y < 0 || _y > 199) return;
    var _cell = (_y >> 3) * 40 + (_x >> 3);
    var _i    = _cell * 8 + (_y & 7);
    var _bit  = 1 << (7 - (_x & 7));
    if (_on) {
        _m.mask[_i] |= _bit;
        _m.cell_base[_cell] = _m.depth;
    } else {
        _m.mask[_i] &= (~_bit) & 0xFF;
    }
}

function scr_sprmask_push_undo(_m) {
    array_push(_m.undo, { mask: array_copy_shallow(_m.mask), base: array_copy_shallow(_m.cell_base) });
    if (array_length(_m.undo) > 20) { array_delete(_m.undo, 0, 1); }
}

/// Overlay surface (320x200, magenta where masked) rebuilt from the layer.
function scr_sprmask_overlay(_m) {
    if (!surface_exists(_m.ov_surf)) {
        _m.ov_surf  = surface_create(320, 200);
        _m.ov_dirty = true;
    }
    if (!_m.ov_dirty) return;
    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_fill(_buf, 0, buffer_u32, 0, 320 * 200 * 4);
    var _px = (170 << 24) | (255 << 16) | (0 << 8) | 255;   // ABGR: magenta, alpha 170
    for (var _c = 0; _c < 1000; _c++) {
        var _cx = (_c mod 40) * 8;
        var _cy = (_c div 40) * 8;
        for (var _r = 0; _r < 8; _r++) {
            var _v = _m.mask[_c * 8 + _r];
            if (_v == 0) continue;
            for (var _b = 0; _b < 8; _b++) {
                if ((_v & (128 >> _b)) != 0) {
                    buffer_poke(_buf, (((_cy + _r) * 320) + _cx + _b) * 4, buffer_u32, _px);
                }
            }
        }
    }
    buffer_set_surface(_buf, _m.ov_surf, 0);
    buffer_delete(_buf);
    _m.ov_dirty = false;
}

/// Brush stamp at hires x,y. MC bitmaps paint whole fat pixels.
function scr_sprmask_brush(_m, _x, _y, _on, _hires, _depth_only) {
    var _s  = _m.brush;
    var _w  = _s;
    if (!_hires) { _w = _s * 2; _x = _x & ~1; }
    var _x0 = _x - (_w div 2);
    var _y0 = _y - (_s div 2);
    if (!_hires) { _x0 = _x0 & ~1; }
    for (var _yy = _y0; _yy < _y0 + _s; _yy++) {
        for (var _xx = _x0; _xx < _x0 + _w; _xx++) {
            if (_xx < 0 || _xx > 319 || _yy < 0 || _yy > 199) continue;
            if (_depth_only) {
                _m.cell_base[(_yy >> 3) * 40 + (_xx >> 3)] = _m.depth;
            } else {
                scr_sprmask_set_px(_m, _xx, _yy, _on);
            }
        }
    }
    if (_depth_only || !surface_exists(_m.ov_surf)) return;
    surface_set_target(_m.ov_surf);
    gpu_set_blendmode_ext(bm_one, bm_zero);
    if (_on) {
        draw_set_colour(c_fuchsia);
        draw_set_alpha(170 / 255);
    } else {
        draw_set_colour(c_black);
        draw_set_alpha(0);
    }
    draw_rectangle(max(0, _x0), max(0, _y0), min(319, _x0 + _w - 1), min(199, _y0 + _s - 1), false);
    draw_set_alpha(1);
    gpu_set_blendmode(bm_normal);
    surface_reset_target();
}

/// Flood fill the same-colour region under x,y (fat pixels on MC bitmaps).
function scr_sprmask_fill(_m, _bmp, _x, _y, _on, _hires) {
    var _target = scr_sprmask_bmp_colour(_bmp, _x, _y, _hires);
    if (_target < 0) return;
    var _gw = 160;
    var _step = 2;
    if (_hires) { _gw = 320; _step = 1; }
    var _seen = array_create(_gw * 200, false);
    var _st = ds_stack_create();
    ds_stack_push(_st, (_y * _gw) + (_x div _step));
    while (!ds_stack_empty(_st)) {
        var _k  = ds_stack_pop(_st);
        if (_seen[_k]) continue;
        _seen[_k] = true;
        var _gx = _k mod _gw;
        var _gy = _k div _gw;
        if (scr_sprmask_bmp_colour(_bmp, _gx * _step, _gy, _hires) != _target) continue;
        for (var _s = 0; _s < _step; _s++) {
            scr_sprmask_set_px(_m, _gx * _step + _s, _gy, _on);
        }
        if (_gx > 0)       { ds_stack_push(_st, _k - 1); }
        if (_gx < _gw - 1) { ds_stack_push(_st, _k + 1); }
        if (_gy > 0)       { ds_stack_push(_st, _k - _gw); }
        if (_gy < 199)     { ds_stack_push(_st, _k + _gw); }
    }
    ds_stack_destroy(_st);
    _m.ov_dirty = true;
}

// --------------------------------------------------------------------
// EDITOR (wide asset panel)
// --------------------------------------------------------------------
function scr_sprmask_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    if (!is_struct(_asset.meta) || !variable_struct_exists(_asset.meta, "mask")) {
        scr_sprmask_create(_asset);
    }
    var _m     = _asset.meta;
    var _press = mouse_check_button_pressed(mb_left);
    var _bmp   = scr_reu_find_asset(_m.ref_bmp);
    if (!is_undefined(_bmp) && _bmp.type != "BITMAP") { _bmp = undefined; }
    var _hires = false;
    if (!is_undefined(_bmp)) { _hires = scr_asset_bmp_is_hires(_bmp); }

    var _button = function(_x1, _y1, _w, _label, _on, _mx2, _my2) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + 18);
        var _bg  = make_color_rgb(38, 38, 58);
        if (_on) { _bg = make_color_rgb(160, 80, 20); }
        if (_hov && !_on) { _bg = make_color_rgb(66, 66, 98); }
        draw_set_color(_bg);
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + 18, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_l(_x1 + _w * 0.5, _y1 + 4, _label);
        draw_set_halign(fa_left);
        return (_hov && mouse_check_button_pressed(mb_left));
    };
    draw_set_font_l(fnt_c64_tiny);

    // ── Toolbar ──
    var _tx = _vx1 + 10;
    var _bl = "BITMAP: (choose)";
    if (_m.ref_bmp != "") { _bl = "BITMAP: " + _m.ref_bmp; }
    if (_button(_tx, _cy, 300, string_copy(_bl, 1, 44), _m.pick_open, _mx, _my)) {
        _m.pick_open   = !_m.pick_open;
        _m.pick_scroll = 0;
    }
    _tx += 310;
    var _tools = ["PAINT", "FILL", "ERASE", "DEPTH"];
    for (var _t = 0; _t < 4; _t++) {
        if (_button(_tx, _cy, 54, _tools[_t], _m.tool == _tools[_t], _mx, _my)) { _m.tool = _tools[_t]; }
        _tx += 58;
    }
    _tx += 8;
    if (_button(_tx, _cy, 64, "BRUSH " + string(_m.brush), false, _mx, _my)) {
        if (_m.brush == 1) { _m.brush = 2; } else if (_m.brush == 2) { _m.brush = 4; } else if (_m.brush == 4) { _m.brush = 8; } else { _m.brush = 1; }
    }
    _tx += 72;
    var _dl = "DEPTH: ALWAYS";
    if (_m.depth != 255) { _dl = "DEPTH: Y " + string(_m.depth); }
    draw_set_color(make_color_rgb(120, 220, 255));
    draw_text_l(_tx, _cy + 4, _dl);
    _tx += 100;
    if (_button(_tx, _cy, 56, "PICK Y", _m.pick_y, _mx, _my)) { _m.pick_y = !_m.pick_y; }
    _tx += 60;
    if (_button(_tx, _cy, 60, "ALWAYS", false, _mx, _my)) { _m.depth = 255; }
    _tx += 68;
    if (_button(_tx, _cy, 50, "CLEAR", false, _mx, _my)) {
        scr_sprmask_push_undo(_m);
        _m.mask = array_create(8000, 0);
        _m.cell_base = array_create(1000, 255);
        _m.ov_dirty = true;
        scr_sprmask_flush(_asset);
        global.addresses_dirty = true;
    }
    _tx += 58;
    var _stat = string(_m.stat_unique) + "/255 CELLS  " + string(buffer_get_size(_asset.buffer)) + " BYTES";
    if (_m.stat_over > 0) { _stat += "  " + string(_m.stat_over) + " CELLS DROPPED!"; }
    draw_set_color(c_yellow);
    draw_text_l(_tx, _cy + 4, _stat);

    // ── Canvas ──
    var _cvx = _vx1 + 10;
    var _cvy = _cy + 28;
    var _sc  = floor(min((_vx2 - _vx1 - 20) / 320, (_vy2 - _cvy - 40) / 200));
    _sc = max(1, _sc);
    var _cw = 320 * _sc;
    var _ch = 200 * _sc;
    draw_set_color(c_black);
    draw_rectangle(_cvx, _cvy, _cvx + _cw, _cvy + _ch, false);
    var _bs = scr_room_map_bmp_surf(_m.ref_bmp);
    var _fl = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    if (_bs != -1) { draw_surface_stretched(_bs, _cvx, _cvy, _cw, _ch); }
    scr_sprmask_overlay(_m);
    draw_surface_stretched(_m.ov_surf, _cvx, _cvy, _cw, _ch);
    gpu_set_tex_filter(_fl);

    var _on_cv = point_in_rectangle(_mx, _my, _cvx, _cvy, _cvx + _cw - 1, _cvy + _ch - 1);
    var _px = clamp(floor((_mx - _cvx) / _sc), 0, 319);
    var _py = clamp(floor((_my - _cvy) / _sc), 0, 199);

    // Depth guide: the hovered cell's depth, or the pick line
    if (_on_cv && !_m.pick_open) {
        var _hc = (_py >> 3) * 40 + (_px >> 3);
        var _gy = -1;
        if (_m.pick_y) {
            _gy = _py;
        } else if (_m.cell_base[_hc] != 255) {
            var _hm = false;
            for (var _r = 0; _r < 8; _r++) { if (_m.mask[_hc * 8 + _r] != 0) { _hm = true; } }
            if (_hm) { _gy = _m.cell_base[_hc]; }
        }
        if (_gy >= 0) {
            draw_set_color(c_aqua);
            draw_line_width(_cvx, _cvy + _gy * _sc, _cvx + _cw, _cvy + _gy * _sc, 2);
            draw_text_l(_cvx + 4, _cvy + _gy * _sc - 14, "DEPTH Y " + string(_gy));
        }
        // Brush outline
        draw_set_color(c_white);
        var _bw = _m.brush;
        if (!_hires) { _bw = _m.brush * 2; }
        var _ox = _px - (_bw div 2);
        if (!_hires) { _ox = _ox & ~1; }
        draw_rectangle(_cvx + _ox * _sc, _cvy + (_py - (_m.brush div 2)) * _sc,
                       _cvx + (_ox + _bw) * _sc, _cvy + (_py - (_m.brush div 2) + _m.brush) * _sc, true);
    }

    draw_set_color(make_color_rgb(95, 95, 115));
    draw_text_l(_cvx, _cvy + _ch + 6,
        "LEFT = TOOL, RIGHT = ERASE, CTRL+Z UNDO.  DEPTH = FRONT EDGE Y OF THE OBJECT: THE SPRITE HIDES ONLY WHILE ITS FEET ARE ABOVE IT.");

    // ── Picker list over the canvas ──
    if (_m.pick_open) {
        var _items = [];
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "BITMAP") { array_push(_items, _a.name); }
        }
        var _rows = 30;
        var _lx = _cvx + 10;
        var _ly = _cvy + 10;
        var _lw = 460;
        draw_set_color(make_color_rgb(16, 19, 29));
        draw_rectangle(_lx, _ly, _lx + _lw, _ly + _rows * 16 + 4, false);
        if (mouse_wheel_up())   { _m.pick_scroll = max(0, _m.pick_scroll - 2); }
        if (mouse_wheel_down()) { _m.pick_scroll = min(max(0, array_length(_items) - _rows), _m.pick_scroll + 2); }
        for (var _li = 0; _li < _rows; _li++) {
            var _ii = _li + _m.pick_scroll;
            if (_ii >= array_length(_items)) break;
            var _ry = _ly + 2 + _li * 16;
            var _rh = point_in_rectangle(_mx, _my, _lx, _ry, _lx + _lw, _ry + 15);
            if (_rh) {
                draw_set_color(make_color_rgb(45, 105, 120));
                draw_rectangle(_lx, _ry, _lx + _lw, _ry + 15, false);
            }
            if (_items[_ii] == _m.ref_bmp) { draw_set_color(c_lime); } else { draw_set_color(c_white); }
            draw_text_l(_lx + 4, _ry + 2, _items[_ii]);
            if (_rh && _press) {
                _m.ref_bmp   = _items[_ii];
                _m.pick_open = false;
                _press = false;
            }
        }
        if (_press && !point_in_rectangle(_mx, _my, _lx, _ly, _lx + _lw, _ly + _rows * 16 + 4)) {
            _m.pick_open = false;
        }
        return;
    }

    // ── Canvas input ──
    if (_on_cv && _press && _m.pick_y) {
        _m.depth  = _py;
        _m.pick_y = false;
        return;
    }
    var _lh = mouse_check_button(mb_left);
    var _rh2 = mouse_check_button(mb_right);
    if (_on_cv && (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))) {
        scr_sprmask_push_undo(_m);
        _m.stroke = true;
        _m.last_x = -1;
        if (_m.tool == "FILL" && mouse_check_button_pressed(mb_left)) {
            scr_sprmask_fill(_m, _bmp, _px, _py, true, _hires);
            _m.stroke = false;
            scr_sprmask_flush(_asset);
            global.addresses_dirty = true;
        }
    }
    if (_m.stroke && (_lh || _rh2) && _on_cv && _m.tool != "FILL") {
        var _on = (_m.tool == "PAINT") && _lh && !_rh2;
        var _depth_only = (_m.tool == "DEPTH") && _lh && !_rh2;
        // Interpolate from the last point so fast strokes stay continuous
        var _sx = _px;
        var _sy = _py;
        if (_m.last_x >= 0) { _sx = _m.last_x; _sy = _m.last_y; }
        var _steps = max(1, max(abs(_px - _sx), abs(_py - _sy)));
        for (var _k = 0; _k <= _steps; _k++) {
            var _ix = round(lerp(_sx, _px, _k / _steps));
            var _iy = round(lerp(_sy, _py, _k / _steps));
            scr_sprmask_brush(_m, _ix, _iy, _on, _hires, _depth_only);
        }
        _m.last_x = _px;
        _m.last_y = _py;
    }
    if (_m.stroke && !_lh && !_rh2) {
        _m.stroke = false;
        scr_sprmask_flush(_asset);
        global.addresses_dirty = true;
    }
    if (scr_ctrl_held() && keyboard_check_pressed(ord("Z")) && array_length(_m.undo) > 0) {
        var _u = array_pop(_m.undo);
        _m.mask = _u.mask;
        _m.cell_base = _u.base;
        _m.ov_dirty = true;
        scr_sprmask_flush(_asset);
        global.addresses_dirty = true;
    }
}

// --------------------------------------------------------------------
// MACRO_SPR_MASK NODE
// --------------------------------------------------------------------
function scr_sprmask_node_defaults(_n) {
    var _inst = _n.instructions[0];
    var _def  = ["macro_spr_mask", "", "0", 20, 0x7F00, 0xF3];
    while (array_length(_inst) < array_length(_def)) {
        array_push(_inst, _def[array_length(_inst)]);
    }
    if (_n.anim_alias == "") { _n.anim_alias = "smask" + string(real(_n.id)); }
}

function scr_sprmask_hex(_v) {
    var _hx = "0123456789ABCDEF";
    var _n  = real(_v) & 0xFFFF;
    var _s  = "";
    for (var _i = 0; _i < 4; _i++) {
        _s = string_char_at(_hx, (_n & 15) + 1) + _s;
        _n = _n >> 4;
    }
    return "$" + _s;
}

function scr_node_draw_macro_spr_mask(_draw_x) {
    scr_sprmask_node_defaults(id);
    var _i  = instructions[0];
    var _vx = _draw_x + 70;
    var _x2 = _draw_x + width - 6;
    var _row = function(_yy, _lbl, _val, _vx1, _vx2, _col) {
        draw_set_font_l(fnt_c64_tiny);
        draw_set_color(make_color_rgb(160, 160, 160));
        scr_node_macro_text_l(_vx1 - 64, _yy, _lbl);
        scr_anim_set_draw_box(_vx1, _yy, _vx2, _yy + 15, _val, _col);
    };
    var _src = string(_i[1]);
    if (_src == "") { _src = "(ROOM_MAP / MASK)"; }
    _row(y + 28, "SOURCE:",  _src, _vx, _x2, c_yellow);
    _row(y + 48, "SPRITES:", string(_i[2]), _vx, _x2, c_lime);
    _row(y + 68, "HOT Y:",   string(_i[3]), _vx, _x2, c_lime);
    _row(y + 88, "WORK:",    scr_sprmask_hex(_i[4]), _vx, _x2, make_color_rgb(120, 220, 255));
    _row(y + 108, "ZP:",     scr_sprmask_hex(_i[5]), _vx, _x2, make_color_rgb(120, 220, 255));
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(140, 140, 140));
    scr_node_macro_text_l(_draw_x + 6, y + 130, "12 ZP BYTES, SAVED + RESTORED");
    draw_set_color(c_yellow);
    scr_node_macro_text_l(_draw_x + 6, y + 146, "JSR " + anim_alias + "_sub");
}

function scr_node_step_macro_spr_mask(_draw_x) {
    scr_sprmask_node_defaults(id);
    var _vx = _draw_x + 70;
    var _x2 = _draw_x + width - 6;
    var _in = function(_yy, _a, _b) { return point_in_rectangle(mouse_x, mouse_y, _a, _yy, _b, _yy + 15); };
    if (_in(y + 28, _vx, _x2)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "MASK_SRC";
        label_picker_scroll     = 0;
        label_picker_target     = id;
        label_picker_index      = 1;
        exit;
    }
    if (_in(y + 48, _vx, _x2))  { scr_anim_set_open_field(id, 2, string(instructions[0][2])); exit; }
    if (_in(y + 68, _vx, _x2))  { scr_anim_set_open_field(id, 3, string(instructions[0][3])); exit; }
    if (_in(y + 88, _vx, _x2))  { scr_anim_set_open_field(id, 4, scr_sprmask_hex(instructions[0][4])); exit; }
    if (_in(y + 108, _vx, _x2)) { scr_anim_set_open_field(id, 5, scr_sprmask_hex(instructions[0][5])); exit; }
    exit;
}

function scr_sprmask_parse_num(_s) {
    _s = string_upper(string_trim(string(_s)));
    if (_s == "") return -1;
    if (string_char_at(_s, 1) == "$") { return real(hex_to_decimal(string_delete(_s, 1, 1))); }
    if (string_digits(_s) == _s) { return real(_s); }
    return -1;
}

function scr_sprmask_commit(_t, _idx, _input) {
    scr_sprmask_node_defaults(_t);
    if (_idx == 2) {
        var _keep = "";
        for (var _i = 1; _i <= string_length(_input); _i++) {
            var _c = string_char_at(_input, _i);
            if ((_c >= "0" && _c <= "7") || _c == ",") { _keep += _c; }
        }
        _t.instructions[0][2] = _keep;
    } else if (_idx == 3) {
        var _v = scr_sprmask_parse_num(_input);
        if (_v >= 0) { _t.instructions[0][3] = clamp(_v, 0, 20); }
    } else if (_idx == 4) {
        var _w = scr_sprmask_parse_num(_input);
        if (_w >= 0) { _t.instructions[0][4] = _w & 0xFFC0; }      // 64-byte aligned
    } else if (_idx == 5) {
        var _z = scr_sprmask_parse_num(_input);
        if (_z >= 0) { _t.instructions[0][5] = clamp(_z, 2, 0xF4); }
    }
    global.addresses_dirty = true;
}

// --------------------------------------------------------------------
// CODEGEN
// --------------------------------------------------------------------
function scr_sprmask_emit(_id, _list) {
    scr_sprmask_node_defaults(_id);
    var _inst  = _id.instructions[0];
    var _p     = _id.anim_alias + "_";
    var _skip  = _p + "skip";
    var _src   = string(_inst[1]);
    var _hot_y = real(_inst[3]);
    var _work  = real(_inst[4]) & 0xFFC0;
    var _z     = real(_inst[5]) & 0xFF;

    // Slots
    var _slots = [];
    var _sl = string_split(string(_inst[2]), ",");
    for (var _s = 0; _s < array_length(_sl); _s++) {
        var _d = string_digits(_sl[_s]);
        if (_d != "") { array_push(_slots, clamp(real(_d), 0, 7)); }
    }
    if (array_length(_slots) == 0) {
        show_debug_message("MACRO_SPR_MASK: no sprite slots");
        return;
    }

    // Mask source: ROOM_MAP (runtime, MACRO_ROOMS' MASK RAM) or SPRITE_MASK (inline blob)
    var _rm     = scr_room_map_find_asset(_src);
    var _sm     = scr_sprmask_find_asset(_src);
    var _ram    = -1;
    var _flag   = "";
    if (!is_undefined(_rm)) {
        with (obj_c64_node) {
            if (node_type == "MACRO_ROOMS" && string(instructions[0][1]) == _src) {
                scr_rooms_node_defaults(id);
                _ram = real(instructions[0][8]);
            }
        }
        if (_ram < 0) {
            show_debug_message("MACRO_SPR_MASK: no ROOMS node uses [" + _src + "]");
            return;
        }
        _flag = scr_room_map_prefix(_src) + "mask_on";
    } else if (is_undefined(_sm)) {
        show_debug_message("MACRO_SPR_MASK: source unresolved [" + _src + "]");
        return;
    }

    // Addresses the code needs
    var _bank_base = _work & 0xC000;
    var _bank_hi   = _bank_base >> 8;
    var _ptrs      = scr_bmp_regions(_bank_base).scr_addr + 0x03F8;
    var _pos_slot  = _slots[0];
    var _zmap = _z;      // map row pointer
    var _zchr = _z + 2;  // char pointer
    var _zsrc = _z + 4;  // source frame
    var _zdst = _z + 6;  // work block
    var _zm   = _z + 8;  // m0..m3 (4 mask bytes of one line)

    array_push(_list, ["jsr",     _p + "sub",  _id]);
    array_push(_list, ["jmp_abs", _skip,       _id]);
    array_push(_list, ["label",   _p + "sub"]);

    // Save the 12 ZP bytes we borrow
    for (var _k = 0; _k < 12; _k++) {
        array_push(_list, ["lda_zp",  _z + _k, _id]);
        array_push(_list, ["sta_lab", _p + "zs" + string(_k), _id]);
    }

    if (_flag != "") {
        array_push(_list, ["lda_lab", _flag,           _id]);
        array_push(_list, ["bne",     _p + "on",       _id]);
        array_push(_list, ["jmp_abs", _p + "restore",  _id]);
        array_push(_list, ["label",   _p + "on"]);
    }

    // Chars base -> cbl/cbh
    if (_ram >= 0) {
        array_push(_list, ["lda_imm", (_ram + 1256) & 0xFF,        _id]);
        array_push(_list, ["sta_lab", _p + "cbl",                  _id]);
        array_push(_list, ["lda_imm", ((_ram + 1256) >> 8) & 0xFF, _id]);
        array_push(_list, ["sta_lab", _p + "cbh",                  _id]);
    } else {
        array_push(_list, ["lda_lab_lo", _p + "chars", _id]);
        array_push(_list, ["sta_lab",    _p + "cbl",   _id]);
        array_push(_list, ["lda_lab_hi", _p + "chars", _id]);
        array_push(_list, ["sta_lab",    _p + "cbh",   _id]);
    }

    // Sprite position -> cell column/row, shift, first sub-row, foot Y
    var _bit = 1 << _pos_slot;
    array_push(_list, ["lda_imm", 0,                        _id]);
    array_push(_list, ["sta_lab", _p + "xh",                _id]);
    array_push(_list, ["lda_abs", 0xD010,                   _id]);
    array_push(_list, ["and_imm", _bit,                     _id]);
    array_push(_list, ["beq",     _p + "xlo",               _id]);
    array_push(_list, ["inc_lab", _p + "xh",                _id]);
    array_push(_list, ["label",   _p + "xlo"]);
    array_push(_list, ["lda_abs", 0xD000 + _pos_slot * 2,   _id]);
    array_push(_list, ["sec",     0,                        _id]);
    array_push(_list, ["sbc_imm", 24,                       _id]);
    array_push(_list, ["sta_lab", _p + "fxl",               _id]);
    array_push(_list, ["lda_lab", _p + "xh",                _id]);
    array_push(_list, ["sbc_imm", 0,                        _id]);
    array_push(_list, ["bpl",     _p + "xok",               _id]);
    array_push(_list, ["jmp_abs", _p + "restore",           _id]);   // left of the bitmap
    array_push(_list, ["label",   _p + "xok"]);
    array_push(_list, ["lsr_a",   0,                        _id]);   // fx >> 3
    array_push(_list, ["lda_lab", _p + "fxl",               _id]);
    array_push(_list, ["ror_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["sta_lab", _p + "cx",                _id]);
    array_push(_list, ["lda_lab", _p + "fxl",               _id]);
    array_push(_list, ["and_imm", 7,                        _id]);
    array_push(_list, ["sta_lab", _p + "sh",                _id]);
    array_push(_list, ["lda_abs", 0xD001 + _pos_slot * 2,   _id]);
    array_push(_list, ["sec",     0,                        _id]);
    array_push(_list, ["sbc_imm", 50,                       _id]);
    array_push(_list, ["bcs",     _p + "yok",               _id]);
    array_push(_list, ["jmp_abs", _p + "restore",           _id]);   // above the bitmap
    array_push(_list, ["label",   _p + "yok"]);
    array_push(_list, ["sta_lab", _p + "fy",                _id]);
    array_push(_list, ["and_imm", 7,                        _id]);
    array_push(_list, ["sta_lab", _p + "rowin",             _id]);
    array_push(_list, ["lda_lab", _p + "fy",                _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["sta_lab", _p + "cy",                _id]);
    array_push(_list, ["lda_lab", _p + "fy",                _id]);
    array_push(_list, ["clc",     0,                        _id]);
    array_push(_list, ["adc_imm", _hot_y,                   _id]);
    array_push(_list, ["sta_lab", _p + "foot",              _id]);

    // ── Resolve the 4x4 cells under the sprite to char pointers ──
    array_push(_list, ["lda_imm", 0,               _id]);
    array_push(_list, ["sta_lab", _p + "any",      _id]);
    array_push(_list, ["sta_lab", _p + "i",        _id]);
    array_push(_list, ["sta_lab", _p + "r",        _id]);
    array_push(_list, ["label",   _p + "rl"]);
    array_push(_list, ["lda_imm", 0,               _id]);
    array_push(_list, ["sta_lab", _p + "rbad",     _id]);
    array_push(_list, ["lda_lab", _p + "cy",       _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_abs", _p + "r",        _id]);
    array_push(_list, ["cmp_imm", 25,              _id]);
    array_push(_list, ["bcc",     _p + "rv",       _id]);
    array_push(_list, ["inc_lab", _p + "rbad",     _id]);
    array_push(_list, ["lda_imm", 0,               _id]);
    array_push(_list, ["label",   _p + "rv"]);
    array_push(_list, ["tax",     0,               _id]);
    array_push(_list, ["lda_abx", _p + "rowlo",    _id]);
    array_push(_list, ["sta_zp",  _zmap,           _id]);
    array_push(_list, ["lda_abx", _p + "rowhi",    _id]);
    array_push(_list, ["sta_zp",  _zmap + 1,       _id]);
    array_push(_list, ["lda_imm", 0,               _id]);
    array_push(_list, ["sta_lab", _p + "c",        _id]);
    array_push(_list, ["label",   _p + "cl"]);
    array_push(_list, ["lda_lab", _p + "rbad",     _id]);
    array_push(_list, ["bne",     _p + "cn",       _id]);
    array_push(_list, ["lda_lab", _p + "cx",       _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_abs", _p + "c",        _id]);
    array_push(_list, ["cmp_imm", 40,              _id]);
    array_push(_list, ["bcs",     _p + "cn",       _id]);
    array_push(_list, ["tay",     0,               _id]);
    array_push(_list, ["lda_izy", _zmap,           _id]);
    array_push(_list, ["beq",     _p + "cn",       _id]);
    array_push(_list, ["sta_lab", _p + "idx",      _id]);
    array_push(_list, ["tax",     0,               _id]);
    array_push(_list, ["lda_lab", _p + "foot",     _id]);
    if (_ram >= 0) {
        array_push(_list, ["cmp_abx", _ram + 1000, _id]);
    } else {
        array_push(_list, ["cmp_abx", _p + "depth", _id]);
    }
    array_push(_list, ["bcs",     _p + "cn",       _id]);   // feet at/below the front edge: in front
    // pointer = chars + idx * 8
    array_push(_list, ["lda_lab", _p + "idx",      _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["sta_lab", _p + "th",       _id]);
    array_push(_list, ["lda_lab", _p + "idx",      _id]);
    array_push(_list, ["asl_a",   0,               _id]);
    array_push(_list, ["asl_a",   0,               _id]);
    array_push(_list, ["asl_a",   0,               _id]);
    array_push(_list, ["clc",     0,               _id]);
    array_push(_list, ["adc_abs", _p + "cbl",      _id]);
    array_push(_list, ["ldx_lab", _p + "i",        _id]);
    array_push(_list, ["sta_abx", _p + "pl",       _id]);
    array_push(_list, ["lda_lab", _p + "th",       _id]);
    array_push(_list, ["adc_abs", _p + "cbh",      _id]);
    array_push(_list, ["sta_abx", _p + "ph",       _id]);
    array_push(_list, ["inc_lab", _p + "any",      _id]);
    array_push(_list, ["jmp_abs", _p + "cnx",      _id]);
    array_push(_list, ["label",   _p + "cn"]);             // unmasked: index 0 ($FF rows)
    array_push(_list, ["ldx_lab", _p + "i",        _id]);
    array_push(_list, ["lda_lab", _p + "cbl",      _id]);
    array_push(_list, ["sta_abx", _p + "pl",       _id]);
    array_push(_list, ["lda_lab", _p + "cbh",      _id]);
    array_push(_list, ["sta_abx", _p + "ph",       _id]);
    array_push(_list, ["label",   _p + "cnx"]);
    array_push(_list, ["inc_lab", _p + "i",        _id]);
    array_push(_list, ["inc_lab", _p + "c",        _id]);
    array_push(_list, ["lda_lab", _p + "c",        _id]);
    array_push(_list, ["cmp_imm", 4,               _id]);
    array_push(_list, ["beq",     _p + "cdone",    _id]);
    array_push(_list, ["jmp_abs", _p + "cl",       _id]);
    array_push(_list, ["label",   _p + "cdone"]);
    array_push(_list, ["inc_lab", _p + "r",        _id]);
    array_push(_list, ["lda_lab", _p + "r",        _id]);
    array_push(_list, ["cmp_imm", 4,               _id]);
    array_push(_list, ["beq",     _p + "rdone",    _id]);
    array_push(_list, ["jmp_abs", _p + "rl",       _id]);
    array_push(_list, ["label",   _p + "rdone"]);
    array_push(_list, ["lda_lab", _p + "any",      _id]);
    array_push(_list, ["bne",     _p + "build",    _id]);
    array_push(_list, ["jmp_abs", _p + "restore",  _id]);   // nothing masked under the sprite

    // ── Build the 21-line mask ──
    array_push(_list, ["label",   _p + "build"]);
    array_push(_list, ["lda_imm", 0,               _id]);
    array_push(_list, ["sta_lab", _p + "line",     _id]);
    array_push(_list, ["sta_lab", _p + "mx",       _id]);
    array_push(_list, ["label",   _p + "ll"]);
    array_push(_list, ["lda_lab", _p + "rowin",    _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["lsr_a",   0,               _id]);
    array_push(_list, ["asl_a",   0,               _id]);
    array_push(_list, ["asl_a",   0,               _id]);
    array_push(_list, ["sta_lab", _p + "cb",       _id]);   // cell row * 4
    array_push(_list, ["lda_lab", _p + "rowin",    _id]);
    array_push(_list, ["and_imm", 7,               _id]);
    array_push(_list, ["sta_lab", _p + "sub",      _id]);
    for (var _c = 0; _c < 4; _c++) {
        array_push(_list, ["lda_lab", _p + "cb",   _id]);
        if (_c > 0) {
            array_push(_list, ["clc",     0,        _id]);
            array_push(_list, ["adc_imm", _c,       _id]);
        }
        array_push(_list, ["tax",     0,           _id]);
        array_push(_list, ["lda_abx", _p + "pl",   _id]);
        array_push(_list, ["sta_zp",  _zchr,       _id]);
        array_push(_list, ["lda_abx", _p + "ph",   _id]);
        array_push(_list, ["sta_zp",  _zchr + 1,   _id]);
        array_push(_list, ["ldy_lab", _p + "sub",  _id]);
        array_push(_list, ["lda_izy", _zchr,       _id]);
        array_push(_list, ["sta_zp",  _zm + _c,    _id]);
    }
    array_push(_list, ["ldx_lab", _p + "sh",       _id]);
    array_push(_list, ["beq",     _p + "ns",       _id]);
    array_push(_list, ["label",   _p + "sl"]);
    array_push(_list, ["asl_zp",  _zm + 3,         _id]);
    array_push(_list, ["rol_zp",  _zm + 2,         _id]);
    array_push(_list, ["rol_zp",  _zm + 1,         _id]);
    array_push(_list, ["rol_zp",  _zm + 0,         _id]);
    array_push(_list, ["dex",     0,               _id]);
    array_push(_list, ["bne",     _p + "sl",       _id]);
    array_push(_list, ["label",   _p + "ns"]);
    array_push(_list, ["ldx_lab", _p + "mx",       _id]);
    for (var _c = 0; _c < 3; _c++) {
        array_push(_list, ["lda_zp",  _zm + _c,    _id]);
        array_push(_list, ["sta_abx", _p + "mask", _id]);
        array_push(_list, ["inx",     0,           _id]);
    }
    array_push(_list, ["stx_lab", _p + "mx",       _id]);
    array_push(_list, ["inc_lab", _p + "rowin",    _id]);
    array_push(_list, ["inc_lab", _p + "line",     _id]);
    array_push(_list, ["lda_lab", _p + "line",     _id]);
    array_push(_list, ["cmp_imm", 21,              _id]);
    array_push(_list, ["beq",     _p + "ldone",    _id]);
    array_push(_list, ["jmp_abs", _p + "ll",       _id]);
    array_push(_list, ["label",   _p + "ldone"]);

    // ── Apply to each slot: frame AND mask -> work block, point the slot at it ──
    for (var _si = 0; _si < array_length(_slots); _si++) {
        var _slot = _slots[_si];
        var _wa   = _work + (_si * 2) * 64;
        var _wb   = _wa + 64;
        var _pa   = ((_wa - _bank_base) >> 6) & 0xFF;
        var _pb   = ((_wb - _bank_base) >> 6) & 0xFF;
        var _q    = _p + "s" + string(_si) + "_";
        array_push(_list, ["lda_abs", _ptrs + _slot, _id]);
        array_push(_list, ["cmp_imm", _pa,           _id]);
        array_push(_list, ["beq",     _q + "old",    _id]);
        array_push(_list, ["cmp_imm", _pb,           _id]);
        array_push(_list, ["beq",     _q + "old",    _id]);
        array_push(_list, ["sta_lab", _q + "sv",     _id]);   // a new frame from the animator
        array_push(_list, ["label",   _q + "old"]);
        array_push(_list, ["lda_lab", _q + "sv",     _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["asl_a",   0,             _id]);
        array_push(_list, ["sta_zp",  _zsrc,         _id]);
        array_push(_list, ["lda_lab", _q + "sv",     _id]);
        array_push(_list, ["lsr_a",   0,             _id]);
        array_push(_list, ["lsr_a",   0,             _id]);
        array_push(_list, ["clc",     0,             _id]);
        array_push(_list, ["adc_imm", _bank_hi,      _id]);
        array_push(_list, ["sta_zp",  _zsrc + 1,     _id]);
        // Pick the block the VIC is not showing
        array_push(_list, ["lda_lab", _p + "tog",    _id]);
        array_push(_list, ["bne",     _q + "b",      _id]);
        array_push(_list, ["lda_imm", _wa & 0xFF,    _id]);
        array_push(_list, ["sta_zp",  _zdst,         _id]);
        array_push(_list, ["lda_imm", _wa >> 8,      _id]);
        array_push(_list, ["sta_zp",  _zdst + 1,     _id]);
        array_push(_list, ["lda_imm", _pa,           _id]);
        array_push(_list, ["sta_lab", _q + "np",     _id]);
        array_push(_list, ["jmp_abs", _q + "go",     _id]);
        array_push(_list, ["label",   _q + "b"]);
        array_push(_list, ["lda_imm", _wb & 0xFF,    _id]);
        array_push(_list, ["sta_zp",  _zdst,         _id]);
        array_push(_list, ["lda_imm", _wb >> 8,      _id]);
        array_push(_list, ["sta_zp",  _zdst + 1,     _id]);
        array_push(_list, ["lda_imm", _pb,           _id]);
        array_push(_list, ["sta_lab", _q + "np",     _id]);
        array_push(_list, ["label",   _q + "go"]);
        array_push(_list, ["ldy_imm", 62,            _id]);
        array_push(_list, ["label",   _q + "cp"]);
        array_push(_list, ["lda_aby", _p + "mask",   _id]);
        array_push(_list, ["sta_lab", _p + "t",      _id]);
        array_push(_list, ["lda_izy", _zsrc,         _id]);
        array_push(_list, ["and_abs", _p + "t",      _id]);
        array_push(_list, ["sta_izy", _zdst,         _id]);
        array_push(_list, ["dey",     0,             _id]);
        array_push(_list, ["bpl",     _q + "cp",     _id]);
        array_push(_list, ["lda_lab", _q + "np",     _id]);
        array_push(_list, ["sta_abs", _ptrs + _slot, _id]);
    }
    array_push(_list, ["lda_lab", _p + "tog",  _id]);
    array_push(_list, ["eor_imm", 1,           _id]);
    array_push(_list, ["sta_lab", _p + "tog",  _id]);
    array_push(_list, ["jmp_abs", _p + "out",  _id]);

    // ── Nothing to mask: hand the animator's frames back ──
    array_push(_list, ["label", _p + "restore"]);
    for (var _si = 0; _si < array_length(_slots); _si++) {
        var _slot = _slots[_si];
        var _wa   = _work + (_si * 2) * 64;
        var _pa   = ((_wa - _bank_base) >> 6) & 0xFF;
        var _q    = _p + "s" + string(_si) + "_";
        array_push(_list, ["lda_abs", _ptrs + _slot, _id]);
        array_push(_list, ["cmp_imm", _pa,           _id]);
        array_push(_list, ["beq",     _q + "rs",     _id]);
        array_push(_list, ["cmp_imm", _pa + 1,       _id]);
        array_push(_list, ["bne",     _q + "rn",     _id]);
        array_push(_list, ["label",   _q + "rs"]);
        array_push(_list, ["lda_lab", _q + "sv",     _id]);
        array_push(_list, ["sta_abs", _ptrs + _slot, _id]);
        array_push(_list, ["label",   _q + "rn"]);
    }
    array_push(_list, ["label", _p + "out"]);
    for (var _k = 0; _k < 12; _k++) {
        array_push(_list, ["lda_lab", _p + "zs" + string(_k), _id]);
        array_push(_list, ["sta_zp",  _z + _k,               _id]);
    }
    array_push(_list, ["rts", 0, _id]);

    // ── State ──
    var _vars = ["cbl", "cbh", "xh", "fxl", "cx", "sh", "fy", "cy", "rowin", "foot", "any", "i", "r",
                 "rbad", "c", "idx", "th", "line", "mx", "cb", "sub", "t", "tog"];
    for (var _k = 0; _k < array_length(_vars); _k++) {
        array_push(_list, ["label", _p + _vars[_k]]);
        array_push(_list, ["byte",  0, _id]);
    }
    for (var _k = 0; _k < 12; _k++) {
        array_push(_list, ["label", _p + "zs" + string(_k)]);
        array_push(_list, ["byte",  0, _id]);
    }
    for (var _si = 0; _si < array_length(_slots); _si++) {
        var _q = _p + "s" + string(_si) + "_";
        array_push(_list, ["label", _q + "sv"]);
        array_push(_list, ["byte",  0, _id]);
        array_push(_list, ["label", _q + "np"]);
        array_push(_list, ["byte",  0, _id]);
    }
    array_push(_list, ["label", _p + "pl"]);
    for (var _k = 0; _k < 16; _k++) { array_push(_list, ["byte", 0, _id]); }
    array_push(_list, ["label", _p + "ph"]);
    for (var _k = 0; _k < 16; _k++) { array_push(_list, ["byte", 0, _id]); }
    array_push(_list, ["label", _p + "mask"]);
    for (var _k = 0; _k < 63; _k++) { array_push(_list, ["byte", 0xFF, _id]); }

    // Map row start table (25 rows of 40)
    if (_ram >= 0) {
        array_push(_list, ["label", _p + "rowlo"]);
        for (var _k = 0; _k < 25; _k++) { array_push(_list, ["byte", (_ram + _k * 40) & 0xFF, _id]); }
        array_push(_list, ["label", _p + "rowhi"]);
        for (var _k = 0; _k < 25; _k++) { array_push(_list, ["byte", ((_ram + _k * 40) >> 8) & 0xFF, _id]); }
    } else {
        // Static mask: the blob lives right here, with a label on every map row
        scr_sprmask_flush(_sm);
        var _cm = scr_sprmask_compile(_sm);
        array_push(_list, ["label", _p + "rowlo"]);
        for (var _k = 0; _k < 25; _k++) { array_push(_list, ["byte_lab_lo", _p + "row" + string(_k), _id]); }
        array_push(_list, ["label", _p + "rowhi"]);
        for (var _k = 0; _k < 25; _k++) { array_push(_list, ["byte_lab_hi", _p + "row" + string(_k), _id]); }
        for (var _k = 0; _k < 1000; _k++) {
            if ((_k mod 40) == 0) { array_push(_list, ["label", _p + "row" + string(_k div 40)]); }
            array_push(_list, ["byte", _cm.map[_k], _id]);
        }
        array_push(_list, ["label", _p + "depth"]);
        for (var _k = 0; _k < 256; _k++) { array_push(_list, ["byte", _cm.base[_k], _id]); }
        array_push(_list, ["label", _p + "chars"]);
        for (var _k = 0; _k < array_length(_cm.chars); _k++) { array_push(_list, ["byte", _cm.chars[_k], _id]); }
    }
    array_push(_list, ["label", _skip]);
}
