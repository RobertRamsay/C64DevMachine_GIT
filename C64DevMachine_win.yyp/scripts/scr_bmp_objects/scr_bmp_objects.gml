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
///
/// LAYOUT
///     managed 1  the editor owns the bytes: every object's graphics then
///                its mask, back to back from the asset address, in list
///                order. Pointers are recomputed whenever anything moves,
///                so objects can be added, deleted, moved and resized.
///     managed 0  IMPORTED: pointers are fixed addresses a game's own code
///                expects (Saboteur). Bytes are edited in place; new
///                objects are appended at the end of the data; delete,
///                move and resize are off so the game's numbering holds.
/// New assets are managed; files saved before the flag existed are
/// imported when they already hold objects.
/// ====================================================================

function scr_bmpobj_create(_asset) {
    _asset.meta = {
        managed   : 1,
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

        // ── EDITOR ONLY (never saved) ──
        undo        : [],   // snapshots, see scr_bmpobj_snapshot
        redo        : [],
        grab_on     : false,  // GRAB FROM BITMAP picker replaces the sheet
        grab_src    : "",     // name of the BITMAP asset being picked from
        grab_sel    : -1,     // [cx1, cy1, cx2, cy2] cells, or -1
        grab_drag   : false,

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
        managed   : _m.managed,
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
    var _keys = ["managed", "objects", "col_major", "bottom_up", "mask_and", "ink", "paper", "sel", "colour_addr", "colour_auto", "poses", "sheet_mode", "layer", "zoom"];
    for (var _k = 0; _k < array_length(_keys); _k++) {
        if (variable_struct_exists(_saved, _keys[_k])) {
            variable_struct_set(_m, _keys[_k], variable_struct_get(_saved, _keys[_k]));
        }
    }
    // Older files: objects already listed came from a game (fixed addresses).
    if (!variable_struct_exists(_saved, "managed")) {
        _m.managed = (array_length(_m.objects) > 0) ? 0 : 1;
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
    var _key = string(_m.ink) + "/" + string(_m.paper) + "/" + string(_m.col_major) + string(_m.bottom_up) + string(_m.mask_and) + "/" + string(_asset.address);
    if (_key != _m.cache_key || array_length(_m.cache_dirty) != _n) {
        // a managed asset that moved address needs its pointers to follow
        scr_bmpobj_sync_ptrs(_asset);
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
/// _enabled = false draws the button greyed out; it still shows its INFO
/// (which should say why it is off) but never reports a click.
function scr_bmpobj_ui_button(_x1, _y1, _w, _h, _label, _on, _mx, _my, _info = "", _enabled = true) {
    var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x1 + _w, _y1 + _h);
    scr_ui_info(_hov, _info);
    var _bg = make_color_rgb(31, 38, 54);
    if (_hov && _enabled) { _bg = make_color_rgb(53, 61, 82); }
    if (_on)  { _bg = make_color_rgb(38, 94, 111); }
    draw_set_color(_bg);
    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
    draw_set_color(make_color_rgb(72, 83, 103));
    if (_on) { draw_set_color(c_aqua); }
    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, true);
    draw_set_color(_enabled ? c_white : make_color_rgb(90, 98, 115));
    draw_set_halign(fa_center);
    draw_text_l(_x1 + _w / 2, _y1 + (_h div 2) - 4, _label);
    draw_set_halign(fa_left);
    return (_enabled && _hov && mouse_check_button_pressed(mb_left));
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
function scr_bmpobj_ui_colour(_x, _y, _label, _col, _mx, _my, _info = "") {
    draw_set_color(make_color_rgb(154, 175, 198));
    draw_text_l(_x, _y + 8, _label);
    var _bx = _x + 50;
    scr_ui_info(point_in_rectangle(_mx, _my, _bx + 28, _y, _bx + 64, _y + 24), _info);
    if (scr_bmpobj_ui_button(_bx, _y, 22, 24, "<", false, _mx, _my, _info)) { _col = (_col + 15) mod 16; }
    draw_set_color(scr_c64_pepto_colour(_col));
    draw_rectangle(_bx + 28, _y, _bx + 64, _y + 24, false);
    draw_set_color(c_white);
    draw_rectangle(_bx + 28, _y, _bx + 64, _y + 24, true);
    if (scr_bmpobj_ui_button(_bx + 70, _y, 22, 24, ">", false, _mx, _my, _info)) { _col = (_col + 1) mod 16; }
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
///   ┌ row 1: OBJECT [+ NEW][DUP][DELETE][RENAME][RESIZE][UP][DOWN]  [UNDO][REDO]  [IMPORT PNG][GRAB FROM BITMAP][EXPORT PNG] ┐
///   ├ row 2: LAYER [GFX][MASK][COMPOSITE]  MASK [AUTO][= INK][GROW][INVERT][CLEAR][FILL]  ZOOM [-] n [+]  INK < >  PAPER < > ┤
///   ├ row 3: LAYOUT  [CELLS][ROWS][MASK AND/OR]  [COLOUR TABLE][AUTO VALUE]                                     n OBJECTS ┤
///   ├ PARTS list ┬ EDIT canvas + info ───────┬ SHEET [PARTS][POSES]  or  GRAB FROM BITMAP picker ──────────────┤
///   └────────────┴───────────────────────────┴─────────────────────────────────────────────────────────────────┘
function scr_bmpobj_editor_body(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "undo"))      { _m.undo = []; _m.redo = []; }
    if (!variable_struct_exists(_m, "grab_on"))   { _m.grab_on = false; _m.grab_src = ""; _m.grab_sel = -1; _m.grab_drag = false; }
    if (!variable_struct_exists(_m, "managed"))   { _m.managed = (array_length(_m.objects) > 0) ? 0 : 1; }
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _pad = 12;
    var _top = _cy + 8;
    var _bottom = _vy2 - 12;
    var _left = _vx1 + _pad;
    var _right = _vx2 - _pad;

    // ── UNDO / REDO KEYS ──
    if (!global.is_any_text_active && scr_ctrl_held()) {
        if (keyboard_check_pressed(ord("Z"))) {
            scr_bmpobj_undo_step(_asset, keyboard_check(vk_shift));
        } else if (keyboard_check_pressed(ord("Y"))) {
            scr_bmpobj_undo_step(_asset, true);
        }
    }

    var _n = array_length(_m.objects);
    var _has = (_n > 0);
    var _managed = (_m.managed == 1);
    if (_has) { _m.sel = clamp(_m.sel, 0, _n - 1); } else { _m.sel = 0; }
    _m.layer = clamp(_m.layer, 0, 2);
    var _o = _has ? _m.objects[_m.sel] : undefined;
    var _lbl_col = make_color_rgb(154, 175, 198);
    var _bh = 24;
    var _r1 = _top;
    var _r2 = _r1 + _bh + 8;
    var _r3 = _r2 + _bh + 8;
    var _fixed_info = "IMPORTED LAYOUT: THE GAME'S OWN CODE NUMBERS THESE OBJECTS AND READS FIXED ADDRESSES, SO THIS IS OFF";

    // ── ROW 1: OBJECTS, UNDO, IMPORT / EXPORT ──
    var _x = _left;
    draw_set_color(_lbl_col);
    draw_text_l(_x, _r1 + 8, "OBJECT");
    _x += 58;
    if (scr_bmpobj_ui_button(_x, _r1, 62, _bh, "+ NEW", false, _mx, _my,
        _managed ? "ADD A BLANK OBJECT AFTER THIS ONE: TYPE ITS SIZE IN CELLS (WIDTH,HEIGHT), UP TO 40,25"
                 : "ADD A BLANK OBJECT AT THE END OF THE DATA: TYPE ITS SIZE IN CELLS (WIDTH,HEIGHT), UP TO 40,25")) {
        scr_prompt_text("New object size in cells (width,height):", "3,3", scr_bmpobj_prompt_cb, {asset:_asset, op:"new", sel:_m.sel});
    }
    _x += 66;
    if (scr_bmpobj_ui_button(_x, _r1, 46, _bh, "DUP", false, _mx, _my, "COPY THIS OBJECT (GRAPHICS, MASK AND COLOUR) AS A NEW OBJECT", _has)) {
        scr_bmpobj_undo_push(_asset);
        var _src = _m.objects[_m.sel];
        scr_bmpobj_add_object(_asset, string_copy(string(_src.name) + " COPY", 1, 24), _src.w, _src.h,
            scr_bmpobj_planes(_asset, _src), scr_bmpobj_get_colour(_asset, _m.sel));
    }
    _x += 50;
    if (scr_bmpobj_ui_button(_x, _r1, 62, _bh, "DELETE", false, _mx, _my,
        _managed ? "DELETE THIS OBJECT. POSES AND MAP ROOMS USING IT DROP IT, LATER OBJECTS MOVE UP ONE NUMBER (CTRL+Z UNDOES)"
                 : _fixed_info, _has && _managed)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_delete_object(_asset, _m.sel);
    }
    _x += 66;
    if (scr_bmpobj_ui_button(_x, _r1, 62, _bh, "RENAME", false, _mx, _my, "GIVE THIS OBJECT A NEW NAME (EDITOR ONLY, THE NAME IS NOT PART OF THE C64 DATA)", _has)) {
        scr_prompt_text("Object name:", _has ? string(_o.name) : "", scr_bmpobj_prompt_cb, {asset:_asset, op:"rename", sel:_m.sel});
    }
    _x += 66;
    if (scr_bmpobj_ui_button(_x, _r1, 62, _bh, "RESIZE", false, _mx, _my,
        _managed ? "CHANGE THIS OBJECT'S SIZE IN CELLS. PIXELS STAY ANCHORED TOP-LEFT, NEW AREA IS SEE-THROUGH"
                 : _fixed_info, _has && _managed)) {
        scr_prompt_text("New size in cells (width,height):", string(_o.w) + "," + string(_o.h), scr_bmpobj_prompt_cb, {asset:_asset, op:"resize", sel:_m.sel});
    }
    _x += 66;
    if (scr_bmpobj_ui_button(_x, _r1, 34, _bh, "UP", false, _mx, _my,
        _managed ? "MOVE THIS OBJECT ONE PLACE EARLIER. ITS NUMBER CHANGES; POSES AND MAP ROOMS ARE UPDATED TO MATCH"
                 : _fixed_info, _has && _managed && _m.sel > 0)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_move_object(_asset, _m.sel, -1);
    }
    _x += 38;
    if (scr_bmpobj_ui_button(_x, _r1, 46, _bh, "DOWN", false, _mx, _my,
        _managed ? "MOVE THIS OBJECT ONE PLACE LATER. ITS NUMBER CHANGES; POSES AND MAP ROOMS ARE UPDATED TO MATCH"
                 : _fixed_info, _has && _managed && _m.sel < _n - 1)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_move_object(_asset, _m.sel, 1);
    }
    _x += 66;
    if (scr_bmpobj_ui_button(_x, _r1, 52, _bh, "UNDO", false, _mx, _my, "UNDO THE LAST CHANGE TO THIS ASSET (CTRL+Z)", array_length(_m.undo) > 0)) {
        scr_bmpobj_undo_step(_asset, false);
    }
    _x += 56;
    if (scr_bmpobj_ui_button(_x, _r1, 52, _bh, "REDO", false, _mx, _my, "REDO THE LAST UNDONE CHANGE (CTRL+Y OR CTRL+SHIFT+Z)", array_length(_m.redo) > 0)) {
        scr_bmpobj_undo_step(_asset, true);
    }
    _x += 76;
    if (scr_bmpobj_ui_button(_x, _r1, 96, _bh, "IMPORT PNG", false, _mx, _my,
        "ADD AN OBJECT FROM A PNG: TRANSPARENT (OR THE TOP-LEFT COLOUR) = SEE-THROUGH, DARK = SOLID BLACK, LIGHT = INK")) {
        scr_bmpobj_import_png(_asset);
    }
    _x += 100;
    if (scr_bmpobj_ui_button(_x, _r1, 140, _bh, "GRAB FROM BITMAP", _m.grab_on, _mx, _my,
        "CUT AN OBJECT OUT OF A BITMAP ASSET: OPENS A PICKER IN PLACE OF THE SHEET (CLICK AGAIN TO CLOSE IT)")) {
        _m.grab_on = !_m.grab_on;
        _m.grab_drag = false;
    }
    _x += 144;
    if (scr_bmpobj_ui_button(_x, _r1, 96, _bh, "EXPORT PNG", false, _mx, _my,
        "SAVE EVERY OBJECT AS ONE PNG SHEET: SEE-THROUGH BACKGROUND, BLACK = SOLID, INK = PREVIEW INK COLOUR", _has)) {
        scr_bmpobj_export_png(_asset);
    }

    // ── ROW 2: LAYER, MASK TOOLS, ZOOM, PREVIEW COLOURS ──
    _x = _left;
    draw_set_color(_lbl_col);
    draw_text_l(_x, _r2 + 8, "LAYER");
    _x += 52;
    var _lnames = ["GFX", "MASK", "COMPOSITE"];
    var _lw = [56, 62, 100];
    var _linfo = ["SHOW AND PAINT THE GRAPHICS PLANE: LMB SETS INK PIXELS, RMB CLEARS THEM",
        "SHOW AND PAINT THE MASK PLANE: LMB MAKES PIXELS SOLID, RMB MAKES THEM TRANSPARENT",
        "SHOW GFX AND MASK TOGETHER: LMB INK, RMB TRANSPARENT, SHIFT+RMB SOLID BLACK"];
    // only the three editor views get buttons (layers 3-5 are map-overlay surfaces)
    for (var _l = 0; _l < array_length(_lnames); _l++) {
        if (scr_bmpobj_ui_button(_x, _r2, _lw[_l], _bh, _lnames[_l], _m.layer == _l, _mx, _my, _linfo[_l])) { _m.layer = _l; }
        _x += _lw[_l] + 4;
    }
    _x += 16;
    draw_set_color(_lbl_col);
    draw_text_l(_x, _r2 + 8, "MASK");
    _x += 42;
    var _mops   = ["auto", "ink", "grow", "invert", "clear", "fill"];
    var _mnames = ["AUTO", "= INK", "GROW", "INVERT", "CLEAR", "FILL"];
    var _mw     = [50, 56, 52, 64, 56, 44];
    var _minfo  = ["REBUILD THE MASK FROM THE GRAPHICS WITH A 1-PIXEL OUTLINE (THE CLASSIC BLACK BORDER)",
        "MAKE EXACTLY THE INK PIXELS SOLID, EVERYTHING ELSE SEE-THROUGH (NO OUTLINE)",
        "GROW THE SOLID AREA BY ONE PIXEL IN EVERY DIRECTION (ADDS AN OUTLINE TO THE CURRENT MASK)",
        "SWAP SOLID AND SEE-THROUGH PIXELS",
        "MAKE THE WHOLE MASK SEE-THROUGH: THE BACKGROUND SHOWS THROUGH EVERY PIXEL",
        "MAKE THE WHOLE OBJECT SOLID: A FULL RECTANGLE THAT HIDES THE BACKGROUND"];
    var _mask_ok = _has && (scr_bmpobj_byte_off(_asset, _o, _o.mask_ptr, 0, 0) >= 0);
    for (var _k = 0; _k < array_length(_mops); _k++) {
        if (scr_bmpobj_ui_button(_x, _r2, _mw[_k], _bh, _mnames[_k], false, _mx, _my,
            _mask_ok ? _minfo[_k] : "THIS OBJECT HAS NO EDITABLE MASK IN THIS ASSET", _mask_ok)) {
            scr_bmpobj_undo_push(_asset);
            scr_bmpobj_mask_op(_asset, _o, _mops[_k]);
            scr_bmpobj_cache_dirty(_asset, _m.sel);
            global.addresses_dirty = true;
        }
        _x += _mw[_k] + 4;
    }
    _x += 16;
    draw_set_color(_lbl_col);
    draw_text_l(_x, _r2 + 8, "ZOOM");
    _x += 44;
    if (scr_bmpobj_ui_button(_x, _r2, 24, _bh, "-", false, _mx, _my, "ZOOM THE EDIT CANVAS OUT (MIN 2X)")) { _m.zoom = max(2, _m.zoom - 2); }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_x + 44, _r2 + 8, string(_m.zoom) + "x");
    draw_set_halign(fa_left);
    if (scr_bmpobj_ui_button(_x + 64, _r2, 24, _bh, "+", false, _mx, _my, "ZOOM THE EDIT CANVAS IN (MAX 24X, SHRINKS TO FIT THE PANEL)")) { _m.zoom = min(24, _m.zoom + 2); }
    _x += 108;
    var _ink = scr_bmpobj_ui_colour(_x, _r2, "INK", _m.ink, _mx, _my, "EDITOR PREVIEW INK COLOUR FOR DRAWING PARTS - < > STEP THROUGH 16 COLOURS");
    _x += 160;
    var _paper = scr_bmpobj_ui_colour(_x, _r2, "PAPER", _m.paper, _mx, _my, "EDITOR PREVIEW PAPER COLOUR FOR DRAWING PARTS - < > STEP THROUGH 16 COLOURS");
    _m.ink = _ink;
    _m.paper = _paper;

    // ── ROW 3: LAYOUT SETTINGS ──
    _x = _left;
    var _lay_txt = _managed ? "LAYOUT: MANAGED" : "LAYOUT: IMPORTED";
    draw_set_color(_managed ? make_color_rgb(120, 220, 160) : c_orange);
    draw_text_l(_x, _r3 + 8, _lay_txt);
    scr_ui_info(point_in_rectangle(_mx, _my, _x, _r3, _x + 150, _r3 + _bh),
        _managed ? "MANAGED: THE EDITOR PACKS EACH OBJECT'S GRAPHICS THEN MASK FROM THE ASSET ADDRESS AND KEEPS EVERY POINTER RIGHT"
                 : "IMPORTED: GRAPHICS AND MASKS SIT AT FIXED ADDRESSES A GAME'S CODE EXPECTS. EDITS CHANGE BYTES IN PLACE");
    _x += 154;
    var _flag_tail = _managed ? " PIXELS ARE KEPT, THE BYTES ARE REWRITTEN" : " IMPORTED: CHANGES HOW THE EXISTING BYTES ARE READ";
    if (scr_bmpobj_ui_button(_x, _r3, 130, _bh, (_m.col_major == 1) ? "CELLS: COLUMNS" : "CELLS: ROWS", false, _mx, _my,
        "HOW EACH OBJECT'S 8X8 CELLS ARE STORED: COLUMN BY COLUMN OR ROW BY ROW." + _flag_tail)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_set_flag(_asset, "col_major", 1 - _m.col_major);
    }
    _x += 134;
    if (scr_bmpobj_ui_button(_x, _r3, 140, _bh, (_m.bottom_up == 1) ? "BYTES: BOTTOM UP" : "BYTES: TOP DOWN", false, _mx, _my,
        "ORDER OF THE 8 BYTES IN A CELL: BOTTOM PIXEL ROW FIRST OR TOP ROW FIRST." + _flag_tail)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_set_flag(_asset, "bottom_up", 1 - _m.bottom_up);
    }
    _x += 144;
    if (scr_bmpobj_ui_button(_x, _r3, 104, _bh, (_m.mask_and == 1) ? "MASK: AND" : "MASK: OR", false, _mx, _my,
        "AND: A SET MASK BIT KEEPS THE BACKGROUND (BLIT = AND MASK, OR GFX). OR: A SET BIT MARKS SOLID PIXELS." + _flag_tail)) {
        scr_bmpobj_undo_push(_asset);
        scr_bmpobj_set_flag(_asset, "mask_and", 1 - _m.mask_and);
    }
    _x += 124;
    var _ca = real(_m.colour_addr);
    if (scr_bmpobj_ui_button(_x, _r3, 170, _bh, (_ca > 0) ? "COLOUR TABLE: $" + string_upper(decimal_to_hex(_ca)) : "COLOUR TABLE: OFF", _ca > 0, _mx, _my,
        "WHERE TO EMIT ONE COLOUR BYTE PER OBJECT FOR GAME CODE TO USE (0 OR OFF = NOT EMITTED). CLICK TO TYPE AN ADDRESS")) {
        scr_prompt_text("Colour table address ($hex or decimal, 0 = off):", (_ca > 0) ? "$" + string_upper(decimal_to_hex(_ca)) : "0",
            scr_bmpobj_prompt_cb, {asset:_asset, op:"colour_addr", sel:_m.sel});
    }
    _x += 174;
    var _cauto = real(_m.colour_auto) & 0xFF;
    if (scr_bmpobj_ui_button(_x, _r3, 130, _bh, "AUTO VALUE: $" + string_upper(decimal_to_hex(_cauto)), false, _mx, _my,
        "THE COLOUR BYTE WRITTEN FOR AUTO-COLOUR OBJECTS: THE VALUE YOUR GAME TREATS AS 'LEAVE THE CELLS ALONE'")) {
        scr_prompt_text("Colour byte for AUTO objects ($hex or decimal, 0-255):", "$" + string_upper(decimal_to_hex(_cauto)),
            scr_bmpobj_prompt_cb, {asset:_asset, op:"colour_auto", sel:_m.sel});
    }
    var _bytes = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    draw_set_color(make_color_rgb(140, 150, 170));
    draw_set_halign(fa_right);
    draw_text_l(_right, _r3 + 8, string(_n) + " OBJECTS   " + string(_bytes) + " BYTES AT $" + string_upper(decimal_to_hex(real(_asset.address))));
    draw_set_halign(fa_left);

    // ── COLUMNS ──
    var _ptop = _r3 + _bh + 12;
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
    if (!_has) {
        draw_set_color(c_ltgray);
        draw_text_l(_lx1 + 8, _ly, "NO OBJECTS YET.");
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_lx1 + 8, _ly + 18, "+ NEW: A BLANK OBJECT");
        draw_text_l(_lx1 + 8, _ly + 34, "IMPORT PNG: FROM A FILE");
        draw_text_l(_lx1 + 8, _ly + 50, "GRAB FROM BITMAP:");
        draw_text_l(_lx1 + 8, _ly + 66, "  CUT ONE FROM A PICTURE");
    }
    scr_ui_info(_has && point_in_rectangle(_mx, _my, _lx1, _ly, _lx2, _bottom), "PARTS: CLICK A PART TO EDIT IT  |  WHEEL: SCROLL THE LIST");
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
        draw_set_color(make_color_rgb(110, 120, 140));
        draw_text_l(_lx1 + 8, _y + 4, string(_i));
        draw_set_color(c_white);
        draw_text_l(_lx1 + 34, _y + 4, string(_oi.name));
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_set_halign(fa_right);
        draw_text_l(_lx2 - 8, _y + 4, string(_oi.w) + "x" + string(_oi.h));
        draw_set_halign(fa_left);
        if (_hov && mouse_check_button_pressed(mb_left)) { _m.sel = _i; }
    }

    // ── EDIT PANEL ──
    if (!_has) {
        scr_bmpobj_ui_panel(_ex1, _ptop, _ex2, _bottom, "EDIT");
        draw_set_color(c_ltgray);
        var _hy = _ptop + 34;
        draw_text_l(_ex1 + 16, _hy,       "BITMAP OBJECTS ARE SOFTWARE SPRITES: GRAPHICS PLUS A MASK");
        draw_text_l(_ex1 + 16, _hy + 18,  "THAT GAME CODE DRAWS INTO A BITMAP SCREEN.");
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_ex1 + 16, _hy + 46,  "1. ADD AN OBJECT: + NEW, IMPORT PNG OR GRAB FROM BITMAP.");
        draw_text_l(_ex1 + 16, _hy + 64,  "2. PAINT IT: GFX = THE PIXELS, MASK = WHERE IT HIDES THE");
        draw_text_l(_ex1 + 16, _hy + 82,  "   BACKGROUND. MASK > AUTO BUILDS ONE WITH AN OUTLINE.");
        draw_text_l(_ex1 + 16, _hy + 100, "3. PLACE THEM IN ROOMS FROM A MAP'S OBJECT LAYER.");
    } else {
    scr_bmpobj_ui_panel(_ex1, _ptop, _ex2, _bottom, "EDIT  " + string(_m.sel) + ": " + string(_o.name) + "   " + string(_o.w) + "x" + string(_o.h) + " cells");
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
    if (point_in_rectangle(_mx, _my, _gx, _gy, _gx + _pw * _s - 1, _gy + _ph * _s - 1)) {
        if (_read_only) {
            scr_ui_info(true, "READ ONLY: THIS PART'S GRAPHICS AND MASK LIVE OUTSIDE THIS ASSET");
        } else if (_m.layer == 0) {
            scr_ui_info(true, "GFX CANVAS: LMB PAINTS INK PIXELS, RMB CLEARS THEM (HOLD AND DRAG)  |  CTRL+Z UNDOES A STROKE");
        } else if (_m.layer == 1) {
            scr_ui_info(true, "MASK CANVAS: LMB MAKES PIXELS SOLID, RMB MAKES THEM TRANSPARENT (HOLD AND DRAG)  |  CTRL+Z UNDOES");
        } else {
            scr_ui_info(true, "COMPOSITE CANVAS: LMB INK, RMB TRANSPARENT, SHIFT+RMB SOLID BLACK (HOLD AND DRAG)  |  CTRL+Z UNDOES");
        }
    }
    if (!_read_only && point_in_rectangle(_mx, _my, _gx, _gy, _gx + _pw * _s - 1, _gy + _ph * _s - 1)) {
        // one undo step per stroke
        if (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) {
            scr_bmpobj_undo_push(_asset);
        }
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
        draw_set_color(_lbl_col);
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
    if (scr_bmpobj_ui_button(_ccx, _iy + 6, 80, 20, "AUTO COL", _ccol < 0, _mx, _my, "TOGGLE: AUTO TAKES THE SCREEN CELLS' COLOURS, OFF GIVES THIS PART A FIXED INK/PAPER")) {
        scr_bmpobj_undo_push(_asset);
        if (_ccol < 0) {
            scr_bmpobj_set_colour(_asset, _m.sel, (1 << 4) | 0);
        } else {
            scr_bmpobj_set_colour(_asset, _m.sel, -1);
        }
        scr_bmpobj_cache_dirty(_asset, _m.sel);
    }
    if (_ccol >= 0) {
        var _cink = scr_bmpobj_ui_colour(_ccx, _iy + 32, "INK", (_ccol >> 4) & 0x0F, _mx, _my, "THIS PART'S FIXED INK COLOUR (STORED IN ITS COLOUR BYTE) - < > STEP THROUGH 16 COLOURS");
        var _cpap = scr_bmpobj_ui_colour(_ccx, _iy + 60, "PAPER", _ccol & 0x0F, _mx, _my, "THIS PART'S FIXED PAPER COLOUR (STORED IN ITS COLOUR BYTE) - < > STEP THROUGH 16 COLOURS");
        var _cnew = (_cink << 4) | _cpap;
        if (_cnew != _ccol) {
            scr_bmpobj_undo_push(_asset);
            scr_bmpobj_set_colour(_asset, _m.sel, _cnew);
        }
    }
    if (_used_in != "") {
        draw_set_color(c_orange);
        draw_text_l(_ex1 + 16, _iy + 44, "USED IN POSES:" + _used_in);
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_ex1 + 16, _iy + 60, "editing this part changes every pose listed");
    }
    }

    // ── SHEET PANEL (or the GRAB FROM BITMAP picker) ──
    if (_m.grab_on) {
        scr_bmpobj_grab_panel(_asset, _sx1, _ptop, _sx2, _bottom, _mx, _my);
        return;
    }
    scr_bmpobj_ui_panel(_sx1, _ptop, _sx2, _bottom, "SHEET  - click a part to edit it, wheel scrolls");
    if (!_has) {
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_sx1 + 12, _ptop + 34, "EVERY OBJECT WILL SHOW HERE.");
        return;
    }
    var _have_poses = (array_length(_m.poses) > 0);
    if (scr_bmpobj_ui_button(_sx2 - 190, _ptop + 2, 88, 17, "PARTS", _m.sheet_mode == 0, _mx, _my, "SHEET SHOWS EVERY PART ON ITS OWN")) { _m.sheet_mode = 0; _m.sheet_scroll = 0; }
    if (_have_poses) {
        if (scr_bmpobj_ui_button(_sx2 - 96, _ptop + 2, 88, 17, "POSES", _m.sheet_mode == 1, _mx, _my, "SHEET SHOWS EACH POSE AS ITS PARTS STACKED TOP TO BOTTOM")) { _m.sheet_mode = 1; _m.sheet_scroll = 0; }
    } else {
        _m.sheet_mode = 0;
    }
    var _st = _ptop + 28;
    var _sb = _bottom - 6;
    scr_ui_info(point_in_rectangle(_mx, _my, _sx1, _st, _sx2, _sb), "SHEET: CLICK A PART TO SELECT IT FOR EDITING  |  WHEEL: SCROLL");
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


/// ====================================================================
/// AUTHORING
/// ====================================================================

/// Both planes of one object as plain bit arrays (row-major, w*8 x h*8).
/// k holds the raw mask bit, so its meaning follows meta.mask_and.
function scr_bmpobj_planes(_asset, _o) {
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    var _g = array_create(_pw * _ph, 0);
    var _k = array_create(_pw * _ph, 0);
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            _g[_py * _pw + _px] = scr_bmpobj_get(_asset, _o, 0, _px, _py);
            _k[_py * _pw + _px] = scr_bmpobj_get(_asset, _o, 1, _px, _py);
        }
    }
    return {w:_o.w, h:_o.h, g:_g, k:_k};
}

/// A see-through plane of _w x _h cells.
function scr_bmpobj_blank_plane(_asset, _w, _h) {
    var _sz = _w * 8 * _h * 8;
    return {w:_w, h:_h, g:array_create(_sz, 0), k:array_create(_sz, real(_asset.meta.mask_and))};
}

/// Planes of every object, in list order.
function scr_bmpobj_all_planes(_asset) {
    var _out = [];
    var _objs = _asset.meta.objects;
    for (var _i = 0; _i < array_length(_objs); _i++) {
        array_push(_out, scr_bmpobj_planes(_asset, _objs[_i]));
    }
    return _out;
}

/// Write one plane into an object's bytes (pointers must already be set).
function scr_bmpobj_write_plane(_asset, _o, _p) {
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            scr_bmpobj_set(_asset, _o, 0, _px, _py, _p.g[_py * _pw + _px]);
            scr_bmpobj_set(_asset, _o, 1, _px, _py, _p.k[_py * _pw + _px]);
        }
    }
}

/// MANAGED: rebuild the whole buffer from planes (one per object, in list
/// order): graphics then mask per object, back to back from the address.
function scr_bmpobj_pack(_asset, _planes) {
    var _m = _asset.meta;
    var _objs = _m.objects;
    var _total = 0;
    for (var _i = 0; _i < array_length(_objs); _i++) { _total += _objs[_i].w * _objs[_i].h * 16; }
    var _size = max(1, _total);
    if (!buffer_exists(_asset.buffer)) {
        _asset.buffer = buffer_create(_size, buffer_fixed, 1);
    } else {
        buffer_resize(_asset.buffer, _size);
    }
    buffer_fill(_asset.buffer, 0, buffer_u8, 0, _size);
    var _base = real(_asset.address);
    var _off = 0;
    for (var _i = 0; _i < array_length(_objs); _i++) {
        var _o = _objs[_i];
        var _cells = _o.w * _o.h;
        _o.gfx_ptr  = _base + _off;
        _o.mask_ptr = _base + _off + _cells * 8;
        _off += _cells * 16;
        scr_bmpobj_write_plane(_asset, _o, _planes[_i]);
    }
    scr_bmpobj_cache_free(_asset);
    _m.cache_dirty = [];
    global.addresses_dirty = true;
}

/// MANAGED: pointers follow the asset address (it can be changed in the
/// header). Moves nothing; only rewrites pointers that went stale.
function scr_bmpobj_sync_ptrs(_asset) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "managed") || _m.managed != 1) return;
    var _base = real(_asset.address);
    var _off = 0;
    for (var _i = 0; _i < array_length(_m.objects); _i++) {
        var _o = _m.objects[_i];
        var _cells = _o.w * _o.h;
        _o.gfx_ptr  = _base + _off;
        _o.mask_ptr = _base + _off + _cells * 8;
        _off += _cells * 16;
    }
}

/// MAP_DATA assets whose object layer uses this asset.
function scr_bmpobj_linked_maps(_asset) {
    var _out = [];
    if (!instance_exists(obj_asset_manager)) return _out;
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = _list[| _i];
        if (_a.type == "MAP_DATA" && variable_struct_exists(_a.meta, "obj_asset") && _a.meta.obj_asset == _asset.name
        &&  variable_struct_exists(_a.meta, "room_objects") && is_array(_a.meta.room_objects)) {
            array_push(_out, _a);
        }
    }
    return _out;
}

/// Object numbers changed: _map[old] = new number, or -1 when deleted.
/// Poses and every linked map's room lists are renumbered to match.
function scr_bmpobj_remap(_asset, _map) {
    var _m = _asset.meta;
    var _np = [];
    for (var _p = 0; _p < array_length(_m.poses); _p++) {
        var _q = [];
        var _pose = _m.poses[_p];
        for (var _k = 0; _k < array_length(_pose); _k++) {
            var _old = real(_pose[_k]);
            if (_old >= 0 && _old < array_length(_map) && _map[_old] >= 0) { array_push(_q, _map[_old]); }
        }
        if (array_length(_q) > 0) { array_push(_np, _q); }
    }
    _m.poses = _np;
    var _maps = scr_bmpobj_linked_maps(_asset);
    for (var _j = 0; _j < array_length(_maps); _j++) {
        var _ro = _maps[_j].meta.room_objects;
        for (var _r = 0; _r < array_length(_ro); _r++) {
            var _src = _ro[_r];
            if (!is_array(_src)) continue;
            var _dst = [];
            for (var _e = 0; _e < array_length(_src); _e++) {
                var _ent = _src[_e];
                var _ix = real(_ent[0]);
                if (_ix >= 0 && _ix < array_length(_map) && _map[_ix] >= 0) {
                    var _copy = array_create(array_length(_ent), 0);
                    array_copy(_copy, 0, _ent, 0, array_length(_ent));
                    _copy[0] = _map[_ix];
                    array_push(_dst, _copy);
                }
            }
            _ro[_r] = _dst;
        }
    }
    global.addresses_dirty = true;
}

/// Add an object. _plane = undefined for a blank one, _colour -1 = AUTO.
/// MANAGED: inserted after the selected object (later numbers shift and are
/// remapped). IMPORTED: appended at the end of the data, numbers unchanged.
function scr_bmpobj_add_object(_asset, _name, _w, _h, _plane, _colour) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    if (is_undefined(_plane)) { _plane = scr_bmpobj_blank_plane(_asset, _w, _h); }
    if (_colour >= 0 && _colour == (real(_m.colour_auto) & 0xFF)) { _colour = -1; }
    var _obj = {name:_name, w:_w, h:_h, gfx_ptr:0, mask_ptr:0, colour:_colour};
    if (_m.managed == 1) {
        var _planes = scr_bmpobj_all_planes(_asset);
        var _at = (_n == 0) ? 0 : clamp(_m.sel + 1, 0, _n);
        var _map = array_create(_n, 0);
        for (var _i = 0; _i < _n; _i++) { _map[_i] = (_i < _at) ? _i : _i + 1; }
        array_insert(_m.objects, _at, _obj);
        array_insert(_planes, _at, _plane);
        scr_bmpobj_pack(_asset, _planes);
        scr_bmpobj_remap(_asset, _map);
        _m.sel = _at;
    } else {
        var _old = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
        var _cells = _w * _h;
        var _size = _old + _cells * 16;
        if (!buffer_exists(_asset.buffer)) {
            _asset.buffer = buffer_create(_size, buffer_fixed, 1);
        } else {
            buffer_resize(_asset.buffer, _size);
        }
        buffer_fill(_asset.buffer, _old, buffer_u8, 0, _cells * 16);
        _obj.gfx_ptr  = real(_asset.address) + _old;
        _obj.mask_ptr = real(_asset.address) + _old + _cells * 8;
        array_push(_m.objects, _obj);
        scr_bmpobj_write_plane(_asset, _obj, _plane);
        scr_bmpobj_cache_free(_asset);
        _m.cache_dirty = [];
        _m.sel = _n;
        global.addresses_dirty = true;
    }
}

/// MANAGED only: delete object _i.
function scr_bmpobj_delete_object(_asset, _i) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    if (_m.managed != 1 || _i < 0 || _i >= _n) return;
    var _planes = scr_bmpobj_all_planes(_asset);
    var _map = array_create(_n, 0);
    for (var _k = 0; _k < _n; _k++) { _map[_k] = (_k < _i) ? _k : ((_k == _i) ? -1 : _k - 1); }
    array_delete(_m.objects, _i, 1);
    array_delete(_planes, _i, 1);
    scr_bmpobj_pack(_asset, _planes);
    scr_bmpobj_remap(_asset, _map);
    _m.sel = clamp(_i, 0, max(0, _n - 2));
}

/// MANAGED only: swap object _i with its neighbour (_dir -1 / +1).
function scr_bmpobj_move_object(_asset, _i, _dir) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    var _j = _i + _dir;
    if (_m.managed != 1 || _i < 0 || _i >= _n || _j < 0 || _j >= _n) return;
    var _planes = scr_bmpobj_all_planes(_asset);
    var _map = array_create(_n, 0);
    for (var _k = 0; _k < _n; _k++) { _map[_k] = _k; }
    _map[_i] = _j;
    _map[_j] = _i;
    var _to = _m.objects[_i];  _m.objects[_i] = _m.objects[_j];  _m.objects[_j] = _to;
    var _tp = _planes[_i];     _planes[_i] = _planes[_j];        _planes[_j] = _tp;
    scr_bmpobj_pack(_asset, _planes);
    scr_bmpobj_remap(_asset, _map);
    _m.sel = _j;
}

/// MANAGED only: new size in cells, pixels anchored top-left.
function scr_bmpobj_resize_object(_asset, _i, _w, _h) {
    var _m = _asset.meta;
    if (_m.managed != 1 || _i < 0 || _i >= array_length(_m.objects)) return;
    var _planes = scr_bmpobj_all_planes(_asset);
    var _src = _planes[_i];
    var _dst = scr_bmpobj_blank_plane(_asset, _w, _h);
    var _spw = _src.w * 8;
    var _dpw = _w * 8;
    for (var _py = 0; _py < min(_src.h, _h) * 8; _py++) {
        for (var _px = 0; _px < min(_src.w, _w) * 8; _px++) {
            _dst.g[_py * _dpw + _px] = _src.g[_py * _spw + _px];
            _dst.k[_py * _dpw + _px] = _src.k[_py * _spw + _px];
        }
    }
    _planes[_i] = _dst;
    _m.objects[_i].w = _w;
    _m.objects[_i].h = _h;
    scr_bmpobj_pack(_asset, _planes);
}

/// Toggle a layout flag. MANAGED keeps every pixel and rewrites the bytes;
/// IMPORTED only changes how the existing bytes are read.
function scr_bmpobj_set_flag(_asset, _key, _val) {
    var _m = _asset.meta;
    if (_m.managed == 1) {
        var _planes = scr_bmpobj_all_planes(_asset);
        if (_key == "mask_and") {
            for (var _i = 0; _i < array_length(_planes); _i++) {
                var _k = _planes[_i].k;
                for (var _p = 0; _p < array_length(_k); _p++) { _k[_p] = 1 - _k[_p]; }
            }
        }
        variable_struct_set(_m, _key, _val);
        scr_bmpobj_pack(_asset, _planes);
    } else {
        variable_struct_set(_m, _key, _val);
        scr_bmpobj_cache_dirty(_asset, -1);
        global.addresses_dirty = true;
    }
}

/// Mask tools: auto (gfx + 1px outline), ink, grow, invert, clear, fill.
function scr_bmpobj_mask_op(_asset, _o, _op) {
    if (_op == "auto") { scr_bmpobj_auto_mask(_asset, _o); return; }
    var _m  = _asset.meta;
    var _pw = _o.w * 8;
    var _ph = _o.h * 8;
    var _solid = array_create(_pw * _ph, 0);
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _v = scr_bmpobj_solid(_asset, _o, _px, _py) ? 1 : 0;
            if (_op == "ink")    { _v = scr_bmpobj_get(_asset, _o, 0, _px, _py); }
            if (_op == "invert") { _v = 1 - _v; }
            if (_op == "clear")  { _v = 0; }
            if (_op == "fill")   { _v = 1; }
            _solid[_py * _pw + _px] = _v;
        }
    }
    if (_op == "grow") {
        var _grown = array_create(_pw * _ph, 0);
        for (var _py = 0; _py < _ph; _py++) {
            for (var _px = 0; _px < _pw; _px++) {
                if (_solid[_py * _pw + _px] == 0) continue;
                for (var _dy = -1; _dy <= 1; _dy++) {
                    for (var _dx = -1; _dx <= 1; _dx++) {
                        var _nx = _px + _dx;
                        var _ny = _py + _dy;
                        if (_nx >= 0 && _ny >= 0 && _nx < _pw && _ny < _ph) { _grown[_ny * _pw + _nx] = 1; }
                    }
                }
            }
        }
        _solid = _grown;
    }
    for (var _py = 0; _py < _ph; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _bit = _solid[_py * _pw + _px];
            if (_m.mask_and == 1) { _bit = 1 - _bit; }
            scr_bmpobj_set(_asset, _o, 1, _px, _py, _bit);
        }
    }
}

/// "$C000", "0xC000" or "49152" -> number; -1 when it does not parse.
function scr_bmpobj_parse_num(_text) {
    var _t = string_upper(string_trim(_text));
    if (_t == "OFF") return 0;
    if (_t == "") return -1;
    var _hex = false;
    if (string_char_at(_t, 1) == "$") { _hex = true; _t = string_delete(_t, 1, 1); }
    else if (string_copy(_t, 1, 2) == "0X") { _hex = true; _t = string_delete(_t, 1, 2); }
    if (_t == "") return -1;
    if (_hex) {
        var _v = 0;
        for (var _i = 1; _i <= string_length(_t); _i++) {
            var _d = string_pos(string_char_at(_t, _i), "0123456789ABCDEF") - 1;
            if (_d < 0) return -1;
            _v = _v * 16 + _d;
        }
        return _v;
    }
    if (string_digits(_t) != _t) return -1;
    return real(_t);
}

/// Answers from the editor's text prompts. _ctx = {asset, op, sel}.
function scr_bmpobj_prompt_cb(_text, _ctx) {
    if (string_trim(_text) == "") return;   // cancelled
    var _a = _ctx.asset;
    var _m = _a.meta;
    var _n = array_length(_m.objects);
    switch (_ctx.op) {
        case "new": {
            var _d = scr_prompt_dimensions(_text, 3, 3);
            scr_bmpobj_undo_push(_a);
            scr_bmpobj_add_object(_a, "OBJECT " + string(_n), clamp(_d.w, 1, 40), clamp(_d.h, 1, 25), undefined, -1);
            break;
        }
        case "rename": {
            if (_ctx.sel < 0 || _ctx.sel >= _n) break;
            scr_bmpobj_undo_push(_a);
            _m.objects[_ctx.sel].name = string_upper(string_copy(string_trim(_text), 1, 24));
            break;
        }
        case "resize": {
            if (_ctx.sel < 0 || _ctx.sel >= _n) break;
            var _o = _m.objects[_ctx.sel];
            var _d2 = scr_prompt_dimensions(_text, _o.w, _o.h);
            var _nw = clamp(_d2.w, 1, 40);
            var _nh = clamp(_d2.h, 1, 25);
            if (_nw == _o.w && _nh == _o.h) break;
            scr_bmpobj_undo_push(_a);
            scr_bmpobj_resize_object(_a, _ctx.sel, _nw, _nh);
            break;
        }
        case "colour_addr": {
            var _v = scr_bmpobj_parse_num(_text);
            if (_v < 0 || _v > 65535) break;
            scr_bmpobj_undo_push(_a);
            _m.colour_addr = _v;
            global.addresses_dirty = true;
            break;
        }
        case "colour_auto": {
            var _v2 = scr_bmpobj_parse_num(_text);
            if (_v2 < 0 || _v2 > 255) break;
            scr_bmpobj_undo_push(_a);
            _m.colour_auto = _v2;
            global.addresses_dirty = true;
            break;
        }
    }
}

/// ── UNDO ──
/// A snapshot is the whole asset: bytes, object list, poses, flags and the
/// room lists of linked maps (delete / move renumber those too).
function scr_bmpobj_snapshot(_asset) {
    var _m = _asset.meta;
    var _sz = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    var _b = buffer_create(max(1, _sz), buffer_fixed, 1);
    if (_sz > 0) { buffer_copy(_asset.buffer, 0, _sz, _b, 0); }
    var _maps = [];
    var _ml = scr_bmpobj_linked_maps(_asset);
    for (var _i = 0; _i < array_length(_ml); _i++) {
        array_push(_maps, {a:_ml[_i], ro:json_stringify(_ml[_i].meta.room_objects)});
    }
    return {buf:_b, size:_sz, objects:json_stringify(_m.objects), poses:json_stringify(_m.poses),
            flags:[_m.col_major, _m.bottom_up, _m.mask_and, _m.managed],
            colour_addr:_m.colour_addr, colour_auto:_m.colour_auto, sel:_m.sel, maps:_maps};
}

function scr_bmpobj_snap_apply(_asset, _s) {
    var _m = _asset.meta;
    var _size = max(1, _s.size);
    if (!buffer_exists(_asset.buffer)) {
        _asset.buffer = buffer_create(_size, buffer_fixed, 1);
    } else {
        buffer_resize(_asset.buffer, _size);
    }
    buffer_copy(_s.buf, 0, _size, _asset.buffer, 0);
    _m.objects = json_parse(_s.objects);
    _m.poses = json_parse(_s.poses);
    _m.col_major = _s.flags[0];
    _m.bottom_up = _s.flags[1];
    _m.mask_and  = _s.flags[2];
    _m.managed   = _s.flags[3];
    _m.colour_addr = _s.colour_addr;
    _m.colour_auto = _s.colour_auto;
    _m.sel = _s.sel;
    for (var _i = 0; _i < array_length(_s.maps); _i++) {
        _s.maps[_i].a.meta.room_objects = json_parse(_s.maps[_i].ro);
    }
    scr_bmpobj_cache_free(_asset);
    _m.cache_dirty = [];
    global.addresses_dirty = true;
}

function scr_bmpobj_undo_free(_list) {
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (buffer_exists(_list[_i].buf)) buffer_delete(_list[_i].buf);
    }
}

/// Call before every change. Keeps 40 steps and clears the redo list.
function scr_bmpobj_undo_push(_asset) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "undo")) { _m.undo = []; _m.redo = []; }
    array_push(_m.undo, scr_bmpobj_snapshot(_asset));
    if (array_length(_m.undo) > 40) {
        if (buffer_exists(_m.undo[0].buf)) buffer_delete(_m.undo[0].buf);
        array_delete(_m.undo, 0, 1);
    }
    scr_bmpobj_undo_free(_m.redo);
    _m.redo = [];
}

/// _redo false = undo (Ctrl+Z), true = redo (Ctrl+Y / Ctrl+Shift+Z).
function scr_bmpobj_undo_step(_asset, _redo) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "undo")) return;
    var _from = _redo ? _m.redo : _m.undo;
    var _to   = _redo ? _m.undo : _m.redo;
    if (array_length(_from) == 0) return;
    var _s = array_pop(_from);
    array_push(_to, scr_bmpobj_snapshot(_asset));
    scr_bmpobj_snap_apply(_asset, _s);
    if (buffer_exists(_s.buf)) buffer_delete(_s.buf);
}

/// ── IMPORT / EXPORT ──

/// One object from a PNG (up to 320x200, cropped to 40x25 cells).
/// Transparent pixels (or, without any transparency, the top-left pixel's
/// colour) are see-through; dark opaque pixels are solid black; the rest ink.
function scr_bmpobj_import_png(_asset) {
    var _path = get_open_filename("PNG image|*.png", "");
    io_clear();   // the native dialog steals the key-up
    if (_path == "" || !file_exists(_path)) return;
    var _spr = sprite_add(_path, 1, false, false, 0, 0);
    if (_spr < 0 || !sprite_exists(_spr)) {
        scr_show_message("BMP OBJECTS: could not load that PNG.");
        return;
    }
    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);
    var _surf = surface_create(_w, _h);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    gpu_set_blendenable(false);
    draw_sprite(_spr, 0, 0, 0);
    gpu_set_blendenable(true);
    surface_reset_target();
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    surface_free(_surf);
    sprite_delete(_spr);

    var _has_alpha = false;
    for (var _i = 0; _i < _w * _h; _i++) {
        if (buffer_peek(_buf, _i * 4 + 3, buffer_u8) < 128) { _has_alpha = true; break; }
    }
    var _kr = buffer_peek(_buf, 0, buffer_u8);
    var _kg = buffer_peek(_buf, 1, buffer_u8);
    var _kb = buffer_peek(_buf, 2, buffer_u8);
    var _cw = clamp(ceil(_w / 8), 1, 40);
    var _ch = clamp(ceil(_h / 8), 1, 25);
    var _plane = scr_bmpobj_blank_plane(_asset, _cw, _ch);
    var _solid = 1 - real(_asset.meta.mask_and);
    var _pw = _cw * 8;
    for (var _y = 0; _y < min(_h, _ch * 8); _y++) {
        for (var _x = 0; _x < min(_w, _pw); _x++) {
            var _o4 = (_y * _w + _x) * 4;
            var _r = buffer_peek(_buf, _o4, buffer_u8);
            var _g = buffer_peek(_buf, _o4 + 1, buffer_u8);
            var _b = buffer_peek(_buf, _o4 + 2, buffer_u8);
            var _a = buffer_peek(_buf, _o4 + 3, buffer_u8);
            var _clear = _has_alpha ? (_a < 128) : (_r == _kr && _g == _kg && _b == _kb);
            if (_clear) continue;
            _plane.k[_y * _pw + _x] = _solid;
            if (0.299 * _r + 0.587 * _g + 0.114 * _b > 48) { _plane.g[_y * _pw + _x] = 1; }
        }
    }
    buffer_delete(_buf);
    var _name = string_upper(string_copy(filename_change_ext(filename_name(_path), ""), 1, 24));
    scr_bmpobj_undo_push(_asset);
    scr_bmpobj_add_object(_asset, _name, _cw, _ch, _plane, -1);
}

/// Every object on one PNG sheet: see-through background, solid = black,
/// ink = the preview ink colour. IMPORT PNG reads it back the same way.
function scr_bmpobj_export_png(_asset) {
    var _m = _asset.meta;
    var _n = array_length(_m.objects);
    if (_n == 0) return;
    var _path = get_save_filename("PNG image|*.png", _asset.name + ".png");
    io_clear();
    if (_path == "") return;
    var _gap = 8;
    var _pos = array_create(_n, 0);
    var _x = 0;
    var _y = 0;
    var _lh = 0;
    var _sw = 1;
    var _sh = 1;
    for (var _i = 0; _i < _n; _i++) {
        var _w = _m.objects[_i].w * 8;
        var _h = _m.objects[_i].h * 8;
        if (_x > 0 && _x + _w > 512) { _x = 0; _y += _lh + _gap; _lh = 0; }
        _pos[_i] = [_x, _y];
        _sw = max(_sw, _x + _w);
        _sh = max(_sh, _y + _h);
        _x += _w + _gap;
        _lh = max(_lh, _h);
    }
    var _surf = surface_create(_sw, _sh);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    gpu_set_blendenable(false);
    for (var _i = 0; _i < _n; _i++) {
        draw_surface(scr_bmpobj_surface(_asset, _i, 3), _pos[_i][0], _pos[_i][1]);
    }
    gpu_set_blendenable(true);
    surface_reset_target();
    surface_save(_surf, _path);
    surface_free(_surf);
}

/// ── GRAB FROM BITMAP ──

/// BITMAP assets with a full picture in them.
function scr_bmpobj_bitmaps() {
    var _out = [];
    if (!instance_exists(obj_asset_manager)) return _out;
    var _list = obj_asset_manager.asset_list;
    for (var _i = 0; _i < ds_list_size(_list); _i++) {
        var _a = _list[| _i];
        if (_a.type == "BITMAP" && buffer_exists(_a.buffer) && buffer_get_size(_a.buffer) >= 9002) {
            array_push(_out, _a);
        }
    }
    return _out;
}

/// New object from a cell rectangle of a BITMAP asset (KLA layout: 2-byte
/// load address, 8000 bitmap bytes, 1000 screen bytes). HiRes: set bits are
/// ink. Multicolour: every non-background pair is ink. The mask is the ink
/// shape (MASK > AUTO adds an outline). A HiRes grab whose cells all share
/// one screen byte takes that as its fixed colour.
function scr_bmpobj_grab(_asset, _bm, _cx, _cy, _w, _h) {
    var _buf = _bm.buffer;
    var _hires = scr_asset_bmp_is_hires(_bm);
    var _plane = scr_bmpobj_blank_plane(_asset, _w, _h);
    var _solid = 1 - real(_asset.meta.mask_and);
    var _pw = _w * 8;
    for (var _py = 0; _py < _h * 8; _py++) {
        for (var _px = 0; _px < _pw; _px++) {
            var _bx = _cx * 8 + _px;
            var _by = _cy * 8 + _py;
            var _b = buffer_peek(_buf, 2 + ((_by >> 3) * 40 + (_bx >> 3)) * 8 + (_by & 7), buffer_u8);
            var _ink = false;
            if (_hires) {
                _ink = ((_b >> (7 - (_bx & 7))) & 1) == 1;
            } else {
                _ink = ((_b >> (6 - (_bx & 6))) & 3) != 0;
            }
            if (_ink) {
                _plane.g[_py * _pw + _px] = 1;
                _plane.k[_py * _pw + _px] = _solid;
            }
        }
    }
    var _col = -1;
    if (_hires) {
        _col = buffer_peek(_buf, 8002 + _cy * 40 + _cx, buffer_u8);
        for (var _ty = _cy; _ty < _cy + _h; _ty++) {
            for (var _tx = _cx; _tx < _cx + _w; _tx++) {
                if (buffer_peek(_buf, 8002 + _ty * 40 + _tx, buffer_u8) != _col) { _col = -1; }
            }
        }
    }
    scr_bmpobj_undo_push(_asset);
    scr_bmpobj_add_object(_asset, string_copy(string_upper(_bm.name), 1, 18) + " " + string(_cx) + "," + string(_cy), _w, _h, _plane, _col);
}

/// The picker that replaces the sheet while GRAB FROM BITMAP is on.
function scr_bmpobj_grab_panel(_asset, _x1, _y1, _x2, _y2, _mx, _my) {
    var _m = _asset.meta;
    scr_bmpobj_ui_panel(_x1, _y1, _x2, _y2, "GRAB FROM BITMAP");
    if (scr_bmpobj_ui_button(_x2 - 70, _y1 + 2, 64, 17, "CLOSE", false, _mx, _my, "CLOSE THE PICKER AND SHOW THE SHEET AGAIN")) {
        _m.grab_on = false;
        _m.grab_drag = false;
        return;
    }
    var _bms = scr_bmpobj_bitmaps();
    if (array_length(_bms) == 0) {
        draw_set_color(c_ltgray);
        draw_text_l(_x1 + 12, _y1 + 34, "NO BITMAP ASSETS WITH A PICTURE YET.");
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_x1 + 12, _y1 + 52, "ADD A BITMAP ASSET, DRAW OR IMPORT A PICTURE, THEN COME BACK.");
        return;
    }
    var _idx = 0;
    for (var _i = 0; _i < array_length(_bms); _i++) { if (_bms[_i].name == _m.grab_src) { _idx = _i; } }
    var _ry = _y1 + 26;
    if (scr_bmpobj_ui_button(_x1 + 10, _ry, 22, 22, "<", false, _mx, _my, "PREVIOUS BITMAP ASSET")) {
        _idx = (_idx + array_length(_bms) - 1) mod array_length(_bms);
        _m.grab_sel = -1;
    }
    if (scr_bmpobj_ui_button(_x1 + 36, _ry, 22, 22, ">", false, _mx, _my, "NEXT BITMAP ASSET")) {
        _idx = (_idx + 1) mod array_length(_bms);
        _m.grab_sel = -1;
    }
    var _bm = _bms[_idx];
    _m.grab_src = _bm.name;
    var _hires = scr_asset_bmp_is_hires(_bm);
    draw_set_color(c_white);
    draw_text_l(_x1 + 66, _ry + 7, string(_bm.name) + (_hires ? "  (HIRES)" : "  (MULTICOLOUR)"));
    var _sel_ok = is_array(_m.grab_sel);
    var _gx1 = 0, _gy1 = 0, _gw = 0, _gh = 0;
    if (_sel_ok) {
        _gx1 = min(_m.grab_sel[0], _m.grab_sel[2]);
        _gy1 = min(_m.grab_sel[1], _m.grab_sel[3]);
        _gw  = abs(_m.grab_sel[2] - _m.grab_sel[0]) + 1;
        _gh  = abs(_m.grab_sel[3] - _m.grab_sel[1]) + 1;
    }
    if (scr_bmpobj_ui_button(_x2 - 130, _ry, 120, 22, "MAKE OBJECT", false, _mx, _my,
        _sel_ok ? "ADD THE SELECTED " + string(_gw) + "X" + string(_gh) + " CELLS AS A NEW OBJECT (MASK = THE INK SHAPE)"
                : "DRAG A RECTANGLE ON THE PICTURE FIRST", _sel_ok && !_m.grab_drag)) {
        scr_bmpobj_grab(_asset, _bm, _gx1, _gy1, _gw, _gh);
    }

    // picture, scaled to fit (whole steps when it fits at 1x or more)
    if (!variable_struct_exists(_bm.meta, "preview_surf") || !surface_exists(_bm.meta.preview_surf)) {
        scr_asset_bmp_build_preview(_bm);
    }
    var _ax1 = _x1 + 10;
    var _ay1 = _ry + 32;
    var _aw = (_x2 - 10) - _ax1;
    var _ah = (_y2 - 26) - _ay1;
    var _sc = min(_aw / 320, _ah / 200);
    if (_sc >= 1) { _sc = floor(_sc); }
    if (_sc <= 0) return;
    var _cs = 8 * _sc;
    if (variable_struct_exists(_bm.meta, "preview_surf") && surface_exists(_bm.meta.preview_surf)) {
        draw_surface_ext(_bm.meta.preview_surf, _ax1, _ay1, _sc, _sc, 0, c_white, 1);
    }
    draw_set_color(make_color_rgb(72, 83, 103));
    draw_rectangle(_ax1 - 1, _ay1 - 1, _ax1 + 320 * _sc, _ay1 + 200 * _sc, true);

    var _over = point_in_rectangle(_mx, _my, _ax1, _ay1, _ax1 + 320 * _sc - 1, _ay1 + 200 * _sc - 1);
    var _ccx = clamp(floor((_mx - _ax1) / _cs), 0, 39);
    var _ccy = clamp(floor((_my - _ay1) / _cs), 0, 24);
    scr_ui_info(_over, "DRAG OVER THE PICTURE TO SELECT WHOLE 8X8 CELLS, THEN MAKE OBJECT. CELL " + string(_ccx) + "," + string(_ccy));
    if (_over && mouse_check_button_pressed(mb_left)) {
        _m.grab_sel = [_ccx, _ccy, _ccx, _ccy];
        _m.grab_drag = true;
    }
    if (_m.grab_drag) {
        if (mouse_check_button(mb_left) && is_array(_m.grab_sel)) {
            _m.grab_sel[2] = _ccx;
            _m.grab_sel[3] = _ccy;
        } else {
            _m.grab_drag = false;
        }
    }
    if (is_array(_m.grab_sel)) {
        var _qx1 = min(_m.grab_sel[0], _m.grab_sel[2]);
        var _qy1 = min(_m.grab_sel[1], _m.grab_sel[3]);
        var _qx2 = max(_m.grab_sel[0], _m.grab_sel[2]) + 1;
        var _qy2 = max(_m.grab_sel[1], _m.grab_sel[3]) + 1;
        draw_set_alpha(0.25);
        draw_set_color(c_yellow);
        draw_rectangle(_ax1 + _qx1 * _cs, _ay1 + _qy1 * _cs, _ax1 + _qx2 * _cs - 1, _ay1 + _qy2 * _cs - 1, false);
        draw_set_alpha(1);
        draw_rectangle(_ax1 + _qx1 * _cs, _ay1 + _qy1 * _cs, _ax1 + _qx2 * _cs - 1, _ay1 + _qy2 * _cs - 1, true);
        draw_set_color(c_white);
        draw_text_l(_ax1, _y2 - 18, "SELECTED " + string(_qx2 - _qx1) + "X" + string(_qy2 - _qy1) + " CELLS FROM " + string(_qx1) + "," + string(_qy1));
    } else {
        draw_set_color(make_color_rgb(140, 150, 170));
        draw_text_l(_ax1, _y2 - 18, "DRAG A RECTANGLE OF CELLS ON THE PICTURE");
    }
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
