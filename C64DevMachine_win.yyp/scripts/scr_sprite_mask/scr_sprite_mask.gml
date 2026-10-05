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
/// MACRO_SPR_MASK node: ["macro_spr_mask", source, slots, hot_y, work, zp, sync]
///   sync = raster line (0 = off). When set, the new sprite position and the
///   masked frame are committed together on that line, so the mask never
///   runs a frame behind the sprite (the 1px shimmer when moving).
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
        mc_mode     : 0,
        zoom        : 1,
        pan_x       : 0,
        pan_y       : 0,
        panning     : false,
        pan_mx      : 0,
        pan_my      : 0,
        click_x     : -1,
        click_y     : -1,
        stroke_x0   : 0,
        stroke_y0   : 0,
        test_on     : false,
        test_x      : 148,
        test_y      : 90,
        test_drag   : false,
        test_gx     : 0,
        test_gy     : 0
    };
    scr_sprmask_flush(_asset);
}

/// Saveable form of the meta (mask + depths as base64, the rest plain).
/// The editor's TEST SPRITE. Uses the real sprite: the frame that the
/// MACRO_SPR node for the mask's first slot shows. Returns
/// { bytes (63), mc, uc, mc1, mc2 } as C64 colour indexes. Falls back to a
/// built-in hires cat when no such sprite exists.
function scr_sprmask_test_sprite(_mask_asset_name) {
    static _cat = [
        $00, $00, $00, $00, $00, $00, $00, $82, $00,
        $00, $C6, $00, $01, $FF, $00, $01, $FF, $00,
        $01, $93, $00, $01, $FF, $00, $03, $EF, $80,
        $00, $FE, $00, $01, $FF, $00, $11, $FE, $00,
        $1F, $FE, $00, $0F, $FE, $00, $03, $FE, $00,
        $03, $FE, $00, $03, $FE, $00, $03, $C6, $00,
        $00, $C6, $00, $00, $C6, $00, $00, $00, $00
    ];
    var _out = { bytes: _cat, mc: false, uc: 1, mc1: 7, mc2: 2 };
    // Which slot does this mask's macro use?
    var _slot = -1;
    with (obj_c64_node) {
        if (node_type == "MACRO_SPR_MASK" && string(instructions[0][1]) == _mask_asset_name) {
            var _d = string_digits(string_char_at(string(instructions[0][2]), 1));
            if (_d != "") { _slot = real(_d); }
        }
    }
    if (_slot < 0) return _out;
    // The SPRITE node that sets up that slot: asset + frame.
    var _spr_name = "";
    var _frame    = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_SPR" && is_real(instructions[0][2]) && real(instructions[0][2]) == _slot) {
            _spr_name = string(instructions[0][1]);
            if (is_real(instructions[0][5])) { _frame = real(instructions[0][5]); }
        }
    }
    if (_spr_name == "" || !instance_exists(obj_asset_manager)) return _out;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type != "SPRITE_SET" || _a.name != _spr_name) continue;
        if (!buffer_exists(_a.buffer) || buffer_get_size(_a.buffer) < (_frame + 1) * 64) return _out;
        var _bytes = array_create(63, 0);
        for (var _b = 0; _b < 63; _b++) {
            _bytes[_b] = buffer_peek(_a.buffer, _frame * 64 + _b, buffer_u8);
        }
        _out.bytes = _bytes;
        var _sm = _a.meta;
        if (variable_struct_exists(_sm, "sprite_mcs") && _frame < array_length(_sm.sprite_mcs)) {
            _out.mc = (real(_sm.sprite_mcs[_frame]) != 0);
        }
        if (variable_struct_exists(_sm, "sprite_ucs") && _frame < array_length(_sm.sprite_ucs)) {
            _out.uc = real(_sm.sprite_ucs[_frame]) & 15;
        }
        if (variable_struct_exists(_sm, "mc1_col")) { _out.mc1 = real(_sm.mc1_col) & 15; }
        if (variable_struct_exists(_sm, "mc2_col")) { _out.mc2 = real(_sm.mc2_col) & 15; }
        return _out;
    }
    return _out;
}

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

/// Overlay: magenta = always foreground, cyan = conditional on feet Y.
function scr_sprmask_overlay(_m) {
    if (!surface_exists(_m.ov_surf)) {
        _m.ov_surf  = surface_create(320, 200);
        _m.ov_dirty = true;
    }
    if (!_m.ov_dirty) return;
    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_fill(_buf, 0, buffer_u32, 0, 320 * 200 * 4);
    for (var _c = 0; _c < 1000; _c++) {
        var _px = (_m.cell_base[_c] == 255)
            ? ((170 << 24) | (255 << 16) | 255)
            : ((170 << 24) | (255 << 16) | (220 << 8)); // ABGR: cyan
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

/// Left edge (hires px) of a brush of _s pixels centred on x. On MC bitmaps
/// the brush is _s fat pixels and always includes the fat pixel under x.
function scr_sprmask_brush_x0(_x, _s, _hires) {
    if (_hires) {
        return _x - (_s div 2);
    }
    return ((_x >> 1) - (_s div 2)) * 2;
}

/// Brush stamp at hires x,y. MC bitmaps paint whole fat pixels.
function scr_sprmask_brush(_m, _x, _y, _on, _hires, _depth_only) {
    var _s  = _m.brush;
    var _w  = _s;
    if (!_hires) { _w = _s * 2; }
    var _x0 = scr_sprmask_brush_x0(_x, _s, _hires);
    var _y0 = _y - (_s div 2);
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
    // A depth change recolours every existing mask pixel in the touched
    // cells, even pixels outside the brush. Rebuild once on the next draw.
    _m.ov_dirty = true;
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
    _m.pick_open = false; // Reference browser is now always visible.
    var _press = mouse_check_button_pressed(mb_left);
    var _bmp   = scr_reu_find_asset(_m.ref_bmp);
    if (!is_undefined(_bmp) && _bmp.type != "BITMAP") { _bmp = undefined; }
    var _hires = false;
    if (!is_undefined(_bmp)) { _hires = scr_asset_bmp_is_hires(_bmp); }

    var _button = function(_x1, _y1, _w, _label, _on, _mx2, _my2) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + 26);
        draw_set_color(_on ? make_color_rgb(38, 94, 111) : (_hov ? make_color_rgb(53, 61, 82) : make_color_rgb(31, 38, 54)));
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + 26, false);
        draw_set_color(_on ? c_aqua : make_color_rgb(72, 83, 103));
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + 26, true);
        draw_set_color(c_white);
        draw_text_l(_x1 + 10, _y1 + 8, _label);
        return (_hov && mouse_check_button_pressed(mb_left));
    };
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _side_x = _vx1 + 18;
    var _side_w = 284;
    var _area_x = _side_x + _side_w + 22;
    var _ref_w = clamp((_vx2 - _area_x) * 0.26, 280, 400);
    var _ref_x = _vx2 - 18 - _ref_w;
    var _area_w = max(320, _ref_x - 18 - _area_x);
    var _top = _cy + 8;
    var _bottom = _vy2 - 18;
    draw_set_color(make_color_rgb(23, 29, 42));
    draw_rectangle(_side_x - 8, _top - 8, _side_x + _side_w + 8, _bottom, false);

    // Behaviour and tool are separate: either rule can paint a new mask
    // or be brushed over an existing one without changing its shape.
    var _conditional = (_m.depth != 255 || _m.pick_y);
    var _ui_mx = _m.pick_open ? -10000 : _mx;
    var _sy = _top;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_side_x, _sy, "1  CHOOSE WHEN THE CAT IS HIDDEN"); _sy += 24;
    if (_button(_side_x, _sy, _side_w, "ALWAYS HIDE THE CAT", !_conditional, _ui_mx, _my)) {
        _m.depth = 255; _m.pick_y = false;
    }
    _sy += 34;
    draw_set_color(c_fuchsia);
    draw_text_l(_side_x + 8, _sy, "MAGENTA: object stays in front."); _sy += 16;
    draw_set_color(c_ltgray);
    draw_text_l(_side_x + 8, _sy, "Use for foreground walls."); _sy += 26;
    if (_button(_side_x, _sy, _side_w, "HIDE ABOVE A Y LINE", _conditional, _ui_mx, _my)) {
        _m.pick_y = true; _m.stroke = false;
    }
    _sy += 34;
    draw_set_color(c_aqua);
    draw_text_l(_side_x + 8, _sy, "CYAN: cat feet above = behind."); _sy += 16;
    draw_set_color(c_ltgray);
    draw_text_l(_side_x + 8, _sy, "At / below the line = in front."); _sy += 22;
    var _line_label = "CLICK HERE, THEN PICK LINE";
    if (_m.pick_y) _line_label = "NOW CLICK THE BITMAP'S Y LINE";
    else if (_m.depth != 255) _line_label = "Y = " + string(_m.depth) + "  |  NEW LINE";
    // With a line chosen, APPLY TO ALL sets it on every cell already masked,
    // so a mask painted before the line was picked can use it too.
    var _line_w = _side_w;
    var _show_all = (_m.depth != 255 && !_m.pick_y);
    if (_show_all) {
        _line_w = _side_w - 110;
    }
    if (_button(_side_x, _sy, _line_w, _line_label, _m.pick_y, _ui_mx, _my)) {
        _m.pick_y = !_m.pick_y; _m.stroke = false;
    }
    if (_show_all) {
        if (_button(_side_x + _side_w - 104, _sy, 104, "APPLY TO ALL", false, _ui_mx, _my)) {
            scr_sprmask_push_undo(_m);
            for (var _ac = 0; _ac < 1000; _ac++) {
                var _am_any = false;
                for (var _ar = 0; _ar < 8; _ar++) {
                    if (_m.mask[_ac * 8 + _ar] != 0) { _am_any = true; }
                }
                if (_am_any) { _m.cell_base[_ac] = _m.depth; }
            }
            _m.ov_dirty = true;
            scr_sprmask_flush(_asset);
            global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
        }
    }
    _sy += 44;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_side_x, _sy, "2  CHOOSE WHAT YOUR BRUSH DOES"); _sy += 24;
    var _tools = ["PAINT", "FILL", "ERASE", "DEPTH"];
    var _names = ["PAINT MASK", "FILL AREA", "ERASE MASK", "CHANGE EXISTING MASK"];
    for (var _t = 0; _t < 4; _t++) {
        if (_button(_side_x, _sy, _side_w, _names[_t], _m.tool == _tools[_t], _ui_mx, _my)) _m.tool = _tools[_t];
        _sy += 32;
    }
    _sy += 8;
    if (_button(_side_x, _sy, _side_w, "BRUSH SIZE: " + string(_m.brush), false, _ui_mx, _my)) {
        _m.brush = (_m.brush == 8) ? 1 : _m.brush * 2;
    }
    // Right click steps the brush down.
    if (point_in_rectangle(_ui_mx, _my, _side_x, _sy, _side_x + _side_w, _sy + 26) && mouse_check_button_pressed(mb_right)) {
        if (_m.brush == 1) {
            _m.brush = 8;
        } else {
            _m.brush = _m.brush div 2;
        }
    }
    _sy += 40;
    draw_set_color(c_white);
    if (_m.tool == "DEPTH") {
        draw_text_l(_side_x, _sy, "Brush over an existing mask.");
        draw_text_l(_side_x, _sy + 16, "Applies the rule from step 1.");
        draw_text_l(_side_x, _sy + 32, "Keeps the painted shape.");
    } else if (_m.tool == "ERASE") {
        draw_text_l(_side_x, _sy, "Brush to remove mask pixels.");
        draw_text_l(_side_x, _sy + 16, "The cat becomes visible there.");
    } else {
        draw_text_l(_side_x, _sy, "Adds mask using the rule above.");
        draw_text_l(_side_x, _sy + 16, "Choosing a rule alone changes");
        draw_text_l(_side_x, _sy + 32, "nothing in the picture.");
    }
    _sy += 58;
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_side_x, _sy, "One rule per 8x8 cell.");
    draw_text_l(_side_x, _sy + 16, "Outlined cells share your rule.");
    _sy += 38;
    if (_button(_side_x, _sy, 134, "UNDO", false, _ui_mx, _my) && array_length(_m.undo) > 0) {
        var _u = array_pop(_m.undo); _m.mask = _u.mask; _m.cell_base = _u.base;
        _m.ov_dirty = true; scr_sprmask_flush(_asset); global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
    }
    if (_button(_side_x + 146, _sy, 138, "CLEAR MASK", false, _ui_mx, _my)) {
        scr_sprmask_push_undo(_m); _m.mask = array_create(8000, 0);
        _m.cell_base = array_create(1000, 255); _m.ov_dirty = true;
        scr_sprmask_flush(_asset); global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
    }
    _sy += 40;
    // TEST SPRITE: a cat face to drag around the scene, masked exactly as the
    // macro would mask a sprite at that spot (hot Y from this asset's node).
    var _test_lbl = "TEST SPRITE: OFF";
    if (_m.test_on) { _test_lbl = "TEST SPRITE: ON  (DRAG IT)"; }
    if (_button(_side_x, _sy, _side_w, _test_lbl, _m.test_on, _ui_mx, _my)) {
        _m.test_on   = !_m.test_on;
        _m.test_drag = false;
    }

    // Reserve the right-hand column for the reference browser.
    draw_set_color(make_color_rgb(154,175,198));
    draw_text_l(_area_x, _top + 8, "MASK CANVAS");
    var _rule = (_m.depth == 255) ? "ALWAYS HIDE THE CAT (MAGENTA)" : "HIDE WHEN FEET ARE ABOVE Y " + string(_m.depth) + " (CYAN)";
    var _action = "PAINT MASK";
    if (_m.tool == "FILL") _action = "FILL AREA";
    if (_m.tool == "ERASE") _action = "ERASE MASK";
    if (_m.tool == "DEPTH") _action = "CHANGE EXISTING MASK";
    var _status = _action + "  /  " + _rule;
    if (_m.tool == "ERASE") _status = "ERASE MASK  /  REMOVE PIXELS TO SHOW THE CAT";
    if (_m.pick_y) _status = "PICK LINE: CLICK WHERE THE OBJECT MEETS THE GROUND. THEN BRUSH TO APPLY.";
    draw_set_color(_m.pick_y ? c_yellow : c_white);
    draw_set_halign(fa_center);
    draw_text_l(_area_x + _area_w * 0.5, _top + 42, _status);
    draw_set_halign(fa_left);
    var _stage_y = _top + 70;
    var _stage_h = _bottom - _stage_y - 44;
    var _sc0 = max(1, floor(min(_area_w / 320, _stage_h / 200)));
    var _sc  = _sc0 * _m.zoom;
    var _cw  = 320 * _sc;
    var _ch  = 200 * _sc;
    var _on_stage = point_in_rectangle(_mx, _my, _area_x, _stage_y, _area_x + _area_w, _stage_y + _stage_h);
    var _cx_mid = floor(_area_x + (_area_w - _cw) * 0.5);
    var _cy_mid = floor(_stage_y + (_stage_h - _ch) * 0.5);

    // Wheel zoom 1x-3x. The bitmap pixel under the pointer stays under it.
    var _zoom_new = _m.zoom;
    if (_on_stage && !global.is_any_text_active) {
        if (mouse_wheel_up())   { _zoom_new = min(3, _m.zoom + 1); }
        if (mouse_wheel_down()) { _zoom_new = max(1, _m.zoom - 1); }
    }
    if (_zoom_new != _m.zoom) {
        var _zbx = (_mx - (_cx_mid + _m.pan_x)) / _sc;
        var _zby = (_my - (_cy_mid + _m.pan_y)) / _sc;
        _m.zoom = _zoom_new;
        _sc     = _sc0 * _m.zoom;
        _cw     = 320 * _sc;
        _ch     = 200 * _sc;
        _cx_mid = floor(_area_x + (_area_w - _cw) * 0.5);
        _cy_mid = floor(_stage_y + (_stage_h - _ch) * 0.5);
        _m.pan_x = round(_mx - _zbx * _sc) - _cx_mid;
        _m.pan_y = round(_my - _zby * _sc) - _cy_mid;
    }
    // Middle-drag pans a zoomed canvas.
    if (_on_stage && mouse_check_button_pressed(mb_middle)) {
        _m.panning = true;
        _m.pan_mx  = _mx;
        _m.pan_my  = _my;
    }
    if (_m.panning) {
        if (mouse_check_button(mb_middle)) {
            _m.pan_x += _mx - _m.pan_mx;
            _m.pan_y += _my - _m.pan_my;
            _m.pan_mx = _mx;
            _m.pan_my = _my;
        } else {
            _m.panning = false;
        }
    }
    // A canvas bigger than the stage always covers it; a smaller one stays centred.
    var _pan_lim_x = max(0, (_cw - _area_w) * 0.5);
    var _pan_lim_y = max(0, (_ch - _stage_h) * 0.5);
    _m.pan_x = clamp(_m.pan_x, -_pan_lim_x, _pan_lim_x);
    _m.pan_y = clamp(_m.pan_y, -_pan_lim_y, _pan_lim_y);
    var _cvx = _cx_mid + _m.pan_x;
    var _cvy = _cy_mid + _m.pan_y;

    // [ and ] step the brush through 1 / 2 / 4 / 8.
    if (!global.is_any_text_active) {
        if (keyboard_check_pressed(221)) { _m.brush = min(8, _m.brush * 2); }
        if (keyboard_check_pressed(219)) { _m.brush = max(1, _m.brush div 2); }
    }

    draw_set_color(make_color_rgb(8, 12, 20));
    draw_rectangle(_area_x, _stage_y, _area_x + _area_w, _stage_y + _stage_h, false);
    // Clip the (possibly zoomed) canvas to the stage. Scissor is in window px.
    var _scis_xs = window_get_width()  / global.gui_w;
    var _scis_ys = window_get_height() / display_get_gui_height();
    gpu_set_scissor(floor(_area_x * _scis_xs), floor(_stage_y * _scis_ys),
                    ceil(_area_w * _scis_xs), ceil(_stage_h * _scis_ys));
    draw_set_color(c_black);
    draw_rectangle(_cvx - 2, _cvy - 2, _cvx + _cw + 2, _cvy + _ch + 2, false);
    var _bs = scr_room_map_bmp_surf(_m.ref_bmp);
    var _fl = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    if (_bs != -1) { draw_surface_stretched(_bs, _cvx, _cvy, _cw, _ch); }
    scr_sprmask_overlay(_m);
    draw_surface_stretched(_m.ov_surf, _cvx, _cvy, _cw, _ch);
    gpu_set_tex_filter(_fl);

    var _on_cv = _on_stage && point_in_rectangle(_mx, _my, _cvx, _cvy, _cvx + _cw - 1, _cvy + _ch - 1);
    var _px = clamp(floor((_mx - _cvx) / _sc), 0, 319);
    var _py = clamp(floor((_my - _cvy) / _sc), 0, 199);

    // Lines. Each masked cell keeps the line it was painted with - that is
    // what the C64 uses. The rule picked in step 1 only applies to paint
    // done from now on, so it is drawn dim and labelled as such; hovering a
    // masked cell shows that cell's own line in bright cyan.
    var _cell_gy = -1;
    if (_on_cv && !_m.pick_open && !_m.pick_y) {
        var _hc = (_py >> 3) * 40 + (_px >> 3);
        if (_m.cell_base[_hc] != 255) {
            for (var _r = 0; _r < 8; _r++) {
                if (_m.mask[_hc * 8 + _r] != 0) { _cell_gy = _m.cell_base[_hc]; }
            }
        }
    }
    if (!_m.pick_open) {
        if (_m.pick_y && _on_cv) {
            draw_set_color(c_aqua);
            draw_line_width(_cvx, _cvy + _py * _sc, _cvx + _cw, _cvy + _py * _sc, 2);
            draw_text_l(_cvx + 4, max(_cvy + 2, _cvy + _py * _sc - 18), "PICK LINE   |   Y " + string(_py));
        } else {
            if (_m.depth != 255 && _m.depth != _cell_gy) {
                draw_set_color(make_color_rgb(0, 120, 140));
                draw_line_width(_cvx, _cvy + _m.depth * _sc, _cvx + _cw, _cvy + _m.depth * _sc, 1);
                draw_text_l(_cvx + 4, max(_cvy + 2, _cvy + _m.depth * _sc - 18),
                    "NEW PAINT LINE   |   Y " + string(_m.depth));
            }
            if (_cell_gy >= 0) {
                draw_set_color(c_aqua);
                draw_line_width(_cvx, _cvy + _cell_gy * _sc, _cvx + _cw, _cvy + _cell_gy * _sc, 2);
                draw_text_l(_cvx + 4, max(_cvy + 2, _cvy + _cell_gy * _sc - 18),
                    "THIS CELL: ABOVE = BEHIND   |   AT / BELOW = IN FRONT   |   Y " + string(_cell_gy));
            }
        }
    }
    if (_on_cv && !_m.pick_open) {
        if ((_m.tool == "DEPTH" || _m.tool == "PAINT") && !_m.pick_y) {
            var _dw = _m.brush;
            if (!_hires) { _dw *= 2; }
            var _dx0 = scr_sprmask_brush_x0(_px, _m.brush, _hires);
            var _dy0 = _py - (_m.brush div 2);
            var _cx0 = clamp(_dx0, 0, 319) >> 3;
            var _cx1 = clamp(_dx0 + _dw - 1, 0, 319) >> 3;
            var _cy0 = clamp(_dy0, 0, 199) >> 3;
            var _cy1 = clamp(_dy0 + _m.brush - 1, 0, 199) >> 3;
            draw_set_color(c_yellow);
            for (var _yy = _cy0; _yy <= _cy1; _yy++) {
                for (var _xx = _cx0; _xx <= _cx1; _xx++) {
                    draw_rectangle(_cvx + _xx * 8 * _sc, _cvy + _yy * 8 * _sc,
                        _cvx + (_xx + 1) * 8 * _sc - 1, _cvy + (_yy + 1) * 8 * _sc - 1, true);
                }
            }
        }
        // Brush outline
        draw_set_color(c_white);
        var _bw = _m.brush;
        if (!_hires) { _bw = _m.brush * 2; }
        var _ox = scr_sprmask_brush_x0(_px, _m.brush, _hires);
        draw_rectangle(_cvx + _ox * _sc, _cvy + (_py - (_m.brush div 2)) * _sc,
                       _cvx + (_ox + _bw) * _sc, _cvy + (_py - (_m.brush div 2) + _m.brush) * _sc, true);
    }

    // ── TEST SPRITE ──
    var _test_hot  = 20;
    var _test_info = "";
    if (_m.test_on) {
        with (obj_c64_node) {
            if (node_type == "MACRO_SPR_MASK" && string(instructions[0][1]) == _asset.name) {
                _test_hot = clamp(real(instructions[0][3]), 0, 20);
            }
        }
        var _ts      = scr_sprmask_test_sprite(_asset.name);
        var _tfoot   = _m.test_y + _test_hot;
        var _hidden  = 0;
        var _shown   = 0;
        // Hires: 24 one-pixel columns. MC: 12 two-pixel columns, and a pixel
        // is hidden if either half is masked (same rule as the macro).
        var _pw    = 1;
        var _pcols = 24;
        if (_ts.mc) {
            _pw    = 2;
            _pcols = 12;
        }
        for (var _tr = 0; _tr < 21; _tr++) {
            for (var _tpc = 0; _tpc < _pcols; _tpc++) {
                var _tbit_x = _tpc * _pw;
                var _tbyte  = _ts.bytes[_tr * 3 + (_tbit_x >> 3)];
                var _tcol_i = -1;
                if (_ts.mc) {
                    var _pair = (_tbyte >> (6 - (_tbit_x & 7))) & 3;
                    if (_pair == 1) { _tcol_i = _ts.mc1; }
                    if (_pair == 2) { _tcol_i = _ts.uc; }
                    if (_pair == 3) { _tcol_i = _ts.mc2; }
                } else {
                    if (((_tbyte >> (7 - (_tbit_x & 7))) & 1) != 0) { _tcol_i = _ts.uc; }
                }
                if (_tcol_i < 0) continue;
                var _behind = false;
                for (var _hp = 0; _hp < _pw; _hp++) {
                    var _bx = _m.test_x + _tbit_x + _hp;
                    var _by = _m.test_y + _tr;
                    if (_bx >= 0 && _bx <= 319 && _by >= 0 && _by <= 199) {
                        var _tcell = (_by >> 3) * 40 + (_bx >> 3);
                        var _tbit  = _m.mask[_tcell * 8 + (_by & 7)] & (128 >> (_bx & 7));
                        if (_tbit != 0 && _tfoot < _m.cell_base[_tcell]) { _behind = true; }
                    }
                }
                if (_behind) { _hidden += 1; continue; }
                _shown += 1;
                var _px0 = _m.test_x + _tbit_x;
                draw_set_color(scr_c64_pepto_colour(_tcol_i));
                draw_rectangle(_cvx + _px0 * _sc, _cvy + (_m.test_y + _tr) * _sc,
                               _cvx + (_px0 + _pw) * _sc - 1, _cvy + (_m.test_y + _tr + 1) * _sc - 1, false);
            }
        }
        // The lines that actually decide it: each masked cell under the
        // sprite, drawn across that cell at its own Y.
        var _lines_txt = "";
        var _seen_lines = [];
        var _cc0 = max(0, floor(_m.test_x / 8));
        var _cc1 = min(39, floor((_m.test_x + 23) / 8));
        var _cr0 = max(0, floor(_m.test_y / 8));
        var _cr1 = min(24, floor((_m.test_y + 20) / 8));
        for (var _cr = _cr0; _cr <= _cr1; _cr++) {
            for (var _cc = _cc0; _cc <= _cc1; _cc++) {
                var _ucell = _cr * 40 + _cc;
                var _um = false;
                for (var _ur = 0; _ur < 8; _ur++) {
                    if (_m.mask[_ucell * 8 + _ur] != 0) { _um = true; }
                }
                if (!_um) continue;
                var _ub = _m.cell_base[_ucell];
                if (_ub != 255) {
                    draw_set_color(c_aqua);
                    draw_line_width(_cvx + _cc * 8 * _sc, _cvy + _ub * _sc,
                                    _cvx + (_cc + 1) * 8 * _sc, _cvy + _ub * _sc, 2);
                }
                var _known = false;
                for (var _sl = 0; _sl < array_length(_seen_lines); _sl++) {
                    if (_seen_lines[_sl] == _ub) { _known = true; }
                }
                if (!_known) {
                    array_push(_seen_lines, _ub);
                    var _ub_txt = "Y " + string(_ub);
                    if (_ub == 255) { _ub_txt = "ALWAYS"; }
                    if (_lines_txt != "") { _lines_txt += ", "; }
                    _lines_txt += _ub_txt;
                }
            }
        }
        // Feet row marker
        draw_set_color(c_yellow);
        draw_line(_cvx + (_m.test_x - 2) * _sc, _cvy + (_tfoot + 1) * _sc,
                  _cvx + (_m.test_x + 26) * _sc, _cvy + (_tfoot + 1) * _sc);
        _test_info = "TEST: FEET Y " + string(_tfoot) + " - ";
        if (_hidden == 0) {
            _test_info += "IN FRONT";
        } else if (_shown == 0) {
            _test_info += "FULLY BEHIND";
        } else {
            _test_info += "PARTLY BEHIND";
        }
        if (_lines_txt != "") {
            _test_info += "   |   CELL LINES UNDER IT: " + _lines_txt;
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    var _cell_info = "";
    if (_on_cv && !_m.pick_open) {
        var _cell = (_py >> 3) * 40 + (_px >> 3);
        var _masked = false;
        for (var _i = 0; _i < 8; _i++) {
            if (_m.mask[_cell * 8 + _i] != 0) _masked = true;
        }
        _cell_info = "CELL " + string(_px >> 3) + "," + string(_py >> 3) + ": ";
        if (!_masked) _cell_info += "NO MASK";
        else if (_m.cell_base[_cell] == 255) _cell_info += "ALWAYS";
        else _cell_info += "Y " + string(_m.cell_base[_cell]);
        _cell_info += "  |  ";
    }
    draw_set_color(c_ltgray);
    draw_set_halign(fa_center);
    if (_test_info != "") {
        draw_set_color(c_yellow);
        draw_text_l(_area_x + _area_w * 0.5, _bottom - 44, _test_info);
        draw_set_color(c_ltgray);
    }
    draw_text_l(_area_x + _area_w * 0.5, _bottom - 28, _cell_info + "RMB: ERASE  |  WHEEL: ZOOM " + string(_m.zoom) + "X  |  [ ]: BRUSH  |  SHIFT: LINE  |  MMB: PAN  |  CTRL+Z: UNDO");
    draw_set_color(_m.stat_over > 0 ? c_red : make_color_rgb(125, 146, 163));
    var _capacity = "Mask shapes: " + string(_m.stat_unique) + "/255";
    if (_m.stat_over > 0) _capacity += "  -  TOO MANY SHAPES: " + string(_m.stat_over) + " CELLS DROPPED";
    draw_text_l(_area_x + _area_w * 0.5, _bottom - 12, _capacity);
    draw_set_halign(fa_left);

    // Persistent reference browser. It cannot dismiss on the opening click,
    // and list presses never become brush strokes on the canvas.
    var _items = [];
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "BITMAP") array_push(_items, _a.name);
    }
    var _lx = _ref_x, _lw = _ref_w;
    var _ly = _top + 34;
    var _rows = max(1, floor((_bottom - _ly - 88) / 24));
    var _list_bottom = _ly + _rows * 24;
    var _over_list = point_in_rectangle(_mx,_my,_lx,_ly,_lx+_lw,_list_bottom);
    _m.pick_scroll = clamp(_m.pick_scroll,0,max(0,array_length(_items)-_rows));
    if (_over_list && mouse_wheel_up()) _m.pick_scroll = max(0,_m.pick_scroll-3);
    if (_over_list && mouse_wheel_down()) _m.pick_scroll = min(max(0,array_length(_items)-_rows),_m.pick_scroll+3);
    draw_set_color(make_color_rgb(23,29,42));
    draw_rectangle(_lx-8,_top-8,_lx+_lw+8,_bottom,false);
    draw_set_color(c_white); draw_text_l(_lx,_top+8,"REFERENCE BITMAP");
    var _detail = _m.ref_bmp;
    for(var _li=0; _li<_rows; _li++) {
        var _ii=_li+_m.pick_scroll;
        if(_ii>=array_length(_items)) break;
        var _ry=_ly+_li*24;
        var _hover=point_in_rectangle(_mx,_my,_lx,_ry,_lx+_lw-10,_ry+23);
        var _selected=_items[_ii]==_m.ref_bmp;
        draw_set_color(_selected ? make_color_rgb(35,83,77) : (_hover ? make_color_rgb(45,70,90) : make_color_rgb(16,19,29)));
        draw_rectangle(_lx,_ry,_lx+_lw-10,_ry+22,false);
        draw_set_color(_selected ? c_lime : c_white);
        draw_text_l(_lx+6,_ry+6,_am.manifest_fit_name(_items[_ii],_lw-24));
        if (_hover) _detail=_items[_ii];
        if (_hover && _press) {
            _m.ref_bmp=_items[_ii]; _m.stroke=false;
            _press=false; mouse_clear(mb_left);
        }
    }
    if (array_length(_items)>_rows) {
        var _track_h=_rows*24;
        var _thumb_h=max(20,_track_h*_rows/array_length(_items));
        var _thumb_y=_ly+(_track_h-_thumb_h)*_m.pick_scroll/(array_length(_items)-_rows);
        draw_set_color(make_color_rgb(45,55,70)); draw_rectangle(_lx+_lw-6,_ly,_lx+_lw,_list_bottom,false);
        draw_set_color(c_aqua); draw_rectangle(_lx+_lw-6,_thumb_y,_lx+_lw,_thumb_y+_thumb_h,false);
    }
    draw_set_color(c_ltgray);
    draw_text_l(_lx,_list_bottom+8,array_length(_items)==0 ? "No bitmap assets available" : "CLICK TO SELECT / WHEEL TO SCROLL");
    // Split long asset identifiers by measured width, including unbroken names.
    draw_set_color(c_white);
    var _remaining=_detail;
    for(var _line=0; _line<3 && _remaining!=""; _line++) {
        var _length=string_length(_remaining);
        while(_length>1 && string_width_l(string_copy(_remaining,1,_length))>_lw-8) _length--;
        var _part=string_copy(_remaining,1,_length);
        _remaining=string_delete(_remaining,1,_length);
        if (_line==2 && _remaining!="") _part=_am.manifest_fit_name(_part+"...",_lw-8);
        draw_text_l(_lx,_list_bottom+28+_line*16,_part);
    }

    // ── Canvas input ──
    if (_on_cv && _press && _m.pick_y) {
        _m.depth  = _py;
        _m.pick_y = false;
        return;
    }
    if (_m.pick_y) return; // Picking a rule is not a paint stroke.
    // TEST SPRITE drag takes the click before any brush stroke.
    if (_m.test_on) {
        var _tpx = floor((_mx - _cvx) / _sc);
        var _tpy = floor((_my - _cvy) / _sc);
        var _over_test = _on_cv && _tpx >= _m.test_x && _tpx < _m.test_x + 24
                      && _tpy >= _m.test_y && _tpy < _m.test_y + 21;
        if (_over_test && _press) {
            _m.test_drag = true;
            _m.test_gx   = _tpx - _m.test_x;
            _m.test_gy   = _tpy - _m.test_y;
        }
        if (_m.test_drag) {
            if (mouse_check_button(mb_left)) {
                _m.test_x = clamp(_tpx - _m.test_gx, -23, 319);
                _m.test_y = clamp(_tpy - _m.test_gy, -20, 199);
            } else {
                _m.test_drag = false;
            }
            return;
        }
    }
    var _lh = mouse_check_button(mb_left);
    var _rh2 = mouse_check_button(mb_right);
    var _shift = keyboard_check(vk_shift);
    if (_on_cv && (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))) {
        scr_sprmask_push_undo(_m);
        _m.stroke = true;
        _m.last_x = -1;
        if (_m.tool == "FILL" && mouse_check_button_pressed(mb_left)) {
            scr_sprmask_fill(_m, _bmp, _px, _py, true, _hires);
            _m.stroke = false;
            scr_sprmask_flush(_asset);
            global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
        } else if (_shift && _m.click_x >= 0) {
            // SHIFT+CLICK: a brush line from the previous click to this one.
            // The stroke then carries on from here.
            _m.last_x = _m.click_x;
            _m.last_y = _m.click_y;
        }
        _m.click_x   = _px;
        _m.click_y   = _py;
        _m.stroke_x0 = _px;
        _m.stroke_y0 = _py;
    }
    if (_m.stroke && (_lh || _rh2) && _on_cv && _m.tool != "FILL") {
        var _on = (_m.tool == "PAINT") && _lh && !_rh2;
        var _depth_only = (_m.tool == "DEPTH") && _lh && !_rh2;
        // SHIFT held while dragging: lock to the stroke's main axis.
        var _tx = _px;
        var _ty = _py;
        if (_shift) {
            if (abs(_px - _m.stroke_x0) >= abs(_py - _m.stroke_y0)) {
                _ty = _m.stroke_y0;
            } else {
                _tx = _m.stroke_x0;
            }
        }
        // Interpolate from the last point so fast strokes stay continuous
        var _sx = _tx;
        _sy = _ty;
        if (_m.last_x >= 0) { _sx = _m.last_x; _sy = _m.last_y; }
        var _steps = max(1, max(abs(_tx - _sx), abs(_ty - _sy)));
        for (var _k = 0; _k <= _steps; _k++) {
            var _ix = round(lerp(_sx, _tx, _k / _steps));
            var _iy = round(lerp(_sy, _ty, _k / _steps));
            scr_sprmask_brush(_m, _ix, _iy, _on, _hires, _depth_only);
        }
        _m.last_x = _tx;
        _m.last_y = _ty;
        _m.click_x = _tx;
        _m.click_y = _ty;
    }
    if (_m.stroke && !_lh && !_rh2) {
        _m.stroke = false;
        scr_sprmask_flush(_asset);
        global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
    }
    if (scr_ctrl_held() && keyboard_check_pressed(ord("Z")) && array_length(_m.undo) > 0) {
        var _u = array_pop(_m.undo);
        _m.mask = _u.mask;
        _m.cell_base = _u.base;
        _m.ov_dirty = true;
        scr_sprmask_flush(_asset);
        global.addresses_dirty = true; global.relayout_frames = max(global.relayout_frames, 1);
    }
}

// --------------------------------------------------------------------
// MACRO_SPR_MASK NODE
// --------------------------------------------------------------------
function scr_sprmask_node_defaults(_n) {
    var _inst = _n.instructions[0];
    var _def  = ["macro_spr_mask", "", "0", 20, 0x7F00, 0xF3, 0];
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
    var _sync_txt = "OFF";
    if (real(_i[6]) > 0) {
        _sync_txt = "ON (LINE $" + string_copy(scr_sprmask_hex(_i[6]), 4, 2) + ")";
    }
    _row(y + 128, "SYNC:",   _sync_txt, _vx, _x2, make_color_rgb(255, 180, 90));
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(140, 140, 140));
    scr_node_macro_text_l(_draw_x + 6, y + 150, "12 ZP BYTES, SAVED + RESTORED");
    draw_set_color(c_yellow);
    scr_node_macro_text_l(_draw_x + 6, y + 166, "JSR " + anim_alias + "_sub");
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
    if (_in(y + 128, _vx, _x2)) {
        // SYNC toggles OFF <-> line $FB (bottom border). No typing needed.
        if (real(instructions[0][6]) > 0) {
            instructions[0][6] = 0;
        } else {
            instructions[0][6] = 0xFB;
        }
        // SYNC changes the macro's size, so re-lay everything after it now.
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        scr_c64_do_update_addresses();
        exit;
    }
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
    } else if (_idx == 6) {
        // Raster line to commit on; blank or 0 = off.
        var _ln = scr_sprmask_parse_num(_input);
        if (_ln < 0) { _ln = 0; }
        _t.instructions[0][6] = clamp(_ln, 0, 254);
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
    var _sync  = clamp(real(_inst[6]), 0, 254);

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

    if (_sync > 0) {
        // Latch where the sprite was just moved to, then put it back where it
        // is drawn now. The commit at the sync line moves it and swaps the
        // frame in the same instant.
        for (var _si = 0; _si < array_length(_slots); _si++) {
            var _slot = _slots[_si];
            var _sb   = 1 << _slot;
            var _q    = _p + "s" + string(_si) + "_";
            array_push(_list, ["lda_abs", 0xD000 + _slot * 2, _id]);
            array_push(_list, ["sta_lab", _q + "nx",          _id]);
            array_push(_list, ["lda_abs", 0xD001 + _slot * 2, _id]);
            array_push(_list, ["sta_lab", _q + "ny",          _id]);
            array_push(_list, ["lda_abs", 0xD010,             _id]);
            array_push(_list, ["and_imm", _sb,                _id]);
            array_push(_list, ["sta_lab", _q + "nh",          _id]);
            array_push(_list, ["lda_lab", _q + "ci",          _id]);
            array_push(_list, ["bne",     _q + "hv",          _id]);
            array_push(_list, ["lda_lab", _q + "nx",          _id]);   // first call: nothing committed yet
            array_push(_list, ["sta_lab", _q + "cx",          _id]);
            array_push(_list, ["lda_lab", _q + "ny",          _id]);
            array_push(_list, ["sta_lab", _q + "cy",          _id]);
            array_push(_list, ["lda_lab", _q + "nh",          _id]);
            array_push(_list, ["sta_lab", _q + "ch",          _id]);
            array_push(_list, ["inc_lab", _q + "ci",          _id]);
            array_push(_list, ["label",   _q + "hv"]);
            array_push(_list, ["lda_lab", _q + "cx",          _id]);
            array_push(_list, ["sta_abs", 0xD000 + _slot * 2, _id]);
            array_push(_list, ["lda_lab", _q + "cy",          _id]);
            array_push(_list, ["sta_abs", 0xD001 + _slot * 2, _id]);
            array_push(_list, ["lda_abs", 0xD010,             _id]);
            array_push(_list, ["and_imm", (~_sb) & 0xFF,      _id]);
            array_push(_list, ["ora_lab", _q + "ch",          _id]);
            array_push(_list, ["sta_abs", 0xD010,             _id]);
        }
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
    if (_sync > 0) {
        array_push(_list, ["lda_lab", _p + "s0_nh",         _id]);
    } else {
        array_push(_list, ["lda_abs", 0xD010,               _id]);
    }
    array_push(_list, ["and_imm", _bit,                     _id]);
    array_push(_list, ["beq",     _p + "xlo",               _id]);
    array_push(_list, ["inc_lab", _p + "xh",                _id]);
    array_push(_list, ["label",   _p + "xlo"]);
    if (_sync > 0) {
        array_push(_list, ["lda_lab", _p + "s0_nx",         _id]);
    } else {
        array_push(_list, ["lda_abs", 0xD000 + _pos_slot * 2, _id]);
    }
    array_push(_list, ["sec",     0,                        _id]);
    array_push(_list, ["sbc_imm", 24,                       _id]);
    array_push(_list, ["sta_lab", _p + "fxl",               _id]);
    array_push(_list, ["lda_lab", _p + "xh",                _id]);
    array_push(_list, ["sbc_imm", 0,                        _id]);
    array_push(_list, ["bpl",     _p + "xok",               _id]);
    // Sprite hanging off the left edge (fx -23..-1): still mask the part over
    // the bitmap. cx goes negative (-3..-1); columns left of the bitmap read
    // as >= 40 unsigned and fall into the unmasked path. Fully off: restore.
    array_push(_list, ["lda_lab", _p + "fxl",               _id]);
    array_push(_list, ["cmp_imm", 233,                      _id]);   // fx >= -23
    array_push(_list, ["bcs",     _p + "xneg",              _id]);
    array_push(_list, ["jmp_abs", _p + "restore",           _id]);   // left of the bitmap
    array_push(_list, ["label",   _p + "xneg"]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["ora_imm", 0xE0,                     _id]);   // sign-extend fx >> 3
    array_push(_list, ["sta_lab", _p + "cx",                _id]);
    array_push(_list, ["jmp_abs", _p + "xcx",               _id]);
    array_push(_list, ["label",   _p + "xok"]);
    array_push(_list, ["lsr_a",   0,                        _id]);   // fx >> 3
    array_push(_list, ["lda_lab", _p + "fxl",               _id]);
    array_push(_list, ["ror_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["lsr_a",   0,                        _id]);
    array_push(_list, ["sta_lab", _p + "cx",                _id]);
    array_push(_list, ["label",   _p + "xcx"]);
    array_push(_list, ["lda_lab", _p + "fxl",               _id]);
    array_push(_list, ["and_imm", 7,                        _id]);
    array_push(_list, ["sta_lab", _p + "sh",                _id]);
    if (_sync > 0) {
        array_push(_list, ["lda_lab", _p + "s0_ny",         _id]);
    } else {
        array_push(_list, ["lda_abs", 0xD001 + _pos_slot * 2, _id]);
    }
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
    array_push(_list, ["sta_lab", _p + "subrow",      _id]);
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
        array_push(_list, ["ldy_lab", _p + "subrow",  _id]);
        array_push(_list, ["lda_izy", _zchr,       _id]);
        array_push(_list, ["sta_zp",  _zm + _c,    _id]);
    }
    array_push(_list, ["ldx_lab", _p + "sh", _id]);
    array_push(_list, ["beq", _p + "ns", _id]);
    array_push(_list, ["cpx_imm", 5, _id]);
    array_push(_list, ["bcc", _p + "sl", _id]);
    array_push(_list, ["lda_imm", 8, _id]);
    array_push(_list, ["sec", 0, _id]);
    array_push(_list, ["sbc_abs", _p + "sh", _id]);
    array_push(_list, ["tax", 0, _id]);
    array_push(_list, ["label", _p + "sr"]);
    array_push(_list, ["lsr_zp", _zm, _id]);
    array_push(_list, ["ror_zp", _zm + 1, _id]);
    array_push(_list, ["ror_zp", _zm + 2, _id]);
    array_push(_list, ["ror_zp", _zm + 3, _id]);
    array_push(_list, ["dex", 0, _id]);
    array_push(_list, ["bne", _p + "sr", _id]);
    for (var _c = 0; _c < 3; _c++) {
        array_push(_list, ["lda_zp", _zm + _c + 1, _id]);
        array_push(_list, ["sta_zp", _zm + _c, _id]);
    }
    array_push(_list, ["jmp_abs", _p + "ns", _id]);
    array_push(_list, ["label", _p + "sl"]);
    array_push(_list, ["asl_zp", _zm + 3, _id]);
    array_push(_list, ["rol_zp", _zm + 2, _id]);
    array_push(_list, ["rol_zp", _zm + 1, _id]);
    array_push(_list, ["rol_zp", _zm, _id]);
    array_push(_list, ["dex", 0, _id]);
    array_push(_list, ["bne", _p + "sl", _id]);
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
        // Select the pixel mode once per sprite, not once per byte.
        array_push(_list, ["lda_abs", 0xD01C, _id]);
        array_push(_list, ["and_imm", 1 << _slot, _id]);
        array_push(_list, ["bne", _q + "mc", _id]);
        array_push(_list, ["ldy_imm", 62, _id]);
        array_push(_list, ["label", _q + "cp"]);
        array_push(_list, ["lda_aby", _p + "mask", _id]);
        array_push(_list, ["and_izy", _zsrc, _id]);
        array_push(_list, ["sta_izy", _zdst, _id]);
        array_push(_list, ["dey", 0, _id]);
        array_push(_list, ["bpl", _q + "cp", _id]);
        array_push(_list, ["jmp_abs", _q + "copied", _id]);
        array_push(_list, ["label", _q + "mc"]);
        array_push(_list, ["ldy_imm", 62, _id]);
        array_push(_list, ["label", _q + "mcp"]);
        // Both bits must survive or the entire multicolour pixel is hidden.
        array_push(_list, ["lda_aby", _p + "mask", _id]);
        array_push(_list, ["sta_zp", _zm, _id]);
        array_push(_list, ["lsr_a", 0, _id]);
        array_push(_list, ["and_zp", _zm, _id]);
        array_push(_list, ["and_imm", 0x55, _id]);
        array_push(_list, ["sta_zp", _zm, _id]);
        array_push(_list, ["asl_a", 0, _id]);
        array_push(_list, ["ora_zp", _zm, _id]);
        array_push(_list, ["and_izy", _zsrc, _id]);
        array_push(_list, ["sta_izy", _zdst, _id]);
        array_push(_list, ["dey", 0, _id]);
        array_push(_list, ["bpl", _q + "mcp", _id]);
        array_push(_list, ["label", _q + "copied"]);
        if (_sync == 0) {
            array_push(_list, ["lda_lab", _q + "np",     _id]);
            array_push(_list, ["sta_abs", _ptrs + _slot, _id]);
        }
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
        if (_sync > 0) {
            array_push(_list, ["sta_lab", _q + "np", _id]);      // default: keep the current frame
        }
        array_push(_list, ["cmp_imm", _pa,           _id]);
        array_push(_list, ["beq",     _q + "rs",     _id]);
        array_push(_list, ["cmp_imm", _pa + 1,       _id]);
        array_push(_list, ["bne",     _q + "rn",     _id]);
        array_push(_list, ["label",   _q + "rs"]);
        array_push(_list, ["lda_lab", _q + "sv",     _id]);
        if (_sync > 0) {
            array_push(_list, ["sta_lab", _q + "np", _id]);
        } else {
            array_push(_list, ["sta_abs", _ptrs + _slot, _id]);
        }
        array_push(_list, ["label",   _q + "rn"]);
    }
    array_push(_list, ["label", _p + "out"]);
    if (_sync > 0) {
        // Wait for the sync line (same two-stage wait as VWAIT literal mode),
        // then move every slot and swap its frame together.
        var _zone = (_sync + 1) & 0xFF;
        array_push(_list, ["label",   _p + "wlo"]);
        array_push(_list, ["lda_abs", 0xD011,     _id]);
        array_push(_list, ["bmi",     _p + "wlo", _id]);
        array_push(_list, ["lda_abs", 0xD012,     _id]);
        array_push(_list, ["cmp_imm", _zone,      _id]);
        array_push(_list, ["bcs",     _p + "wlo", _id]);
        array_push(_list, ["label",   _p + "whi"]);
        array_push(_list, ["lda_abs", 0xD011,     _id]);
        array_push(_list, ["bmi",     _p + "wdn", _id]);
        array_push(_list, ["lda_abs", 0xD012,     _id]);
        array_push(_list, ["cmp_imm", _zone,      _id]);
        array_push(_list, ["bcc",     _p + "whi", _id]);
        array_push(_list, ["label",   _p + "wdn"]);
        for (var _si = 0; _si < array_length(_slots); _si++) {
            var _slot = _slots[_si];
            var _sb   = 1 << _slot;
            var _q    = _p + "s" + string(_si) + "_";
            array_push(_list, ["lda_lab", _q + "nx",          _id]);
            array_push(_list, ["sta_abs", 0xD000 + _slot * 2, _id]);
            array_push(_list, ["sta_lab", _q + "cx",          _id]);
            array_push(_list, ["lda_lab", _q + "ny",          _id]);
            array_push(_list, ["sta_abs", 0xD001 + _slot * 2, _id]);
            array_push(_list, ["sta_lab", _q + "cy",          _id]);
            array_push(_list, ["lda_abs", 0xD010,             _id]);
            array_push(_list, ["and_imm", (~_sb) & 0xFF,      _id]);
            array_push(_list, ["ora_lab", _q + "nh",          _id]);
            array_push(_list, ["sta_abs", 0xD010,             _id]);
            array_push(_list, ["lda_lab", _q + "nh",          _id]);
            array_push(_list, ["sta_lab", _q + "ch",          _id]);
            array_push(_list, ["lda_lab", _q + "np",          _id]);
            array_push(_list, ["sta_abs", _ptrs + _slot,      _id]);
        }
    }
    for (var _k = 0; _k < 12; _k++) {
        array_push(_list, ["lda_lab", _p + "zs" + string(_k), _id]);
        array_push(_list, ["sta_zp",  _z + _k,               _id]);
    }
    array_push(_list, ["rts", 0, _id]);

    // ── State ──
    var _vars = ["cbl", "cbh", "xh", "fxl", "cx", "sh", "fy", "cy", "rowin", "foot", "any", "i", "r",
                 "rbad", "c", "idx", "th", "line", "mx", "cb", "subrow", "t", "tog"];
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
        if (_sync > 0) {
            var _sv_names = ["nx", "ny", "nh", "cx", "cy", "ch", "ci"];
            for (var _k = 0; _k < array_length(_sv_names); _k++) {
                array_push(_list, ["label", _q + _sv_names[_k]]);
                array_push(_list, ["byte",  0, _id]);
            }
        }
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
