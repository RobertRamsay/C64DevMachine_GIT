/// _full = true skips the disk cache and always decodes (scr_asset_bmp_ensure_decoded).
function scr_asset_bmp_build_preview(_asset, _full = false) {

	// check guard
    if (!buffer_exists(_asset.buffer)) exit;
    var _buf = _asset.buffer;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _min_size = _is_hires ? 9002 : 10003;
    if (buffer_get_size(_buf) < _min_size) exit;
    
    if (variable_struct_exists(_asset.meta, "preview_surf") &&
        surface_exists(_asset.meta.preview_surf)) {
        surface_free(_asset.meta.preview_surf);
    }
    if (!_is_hires) {
        _asset.meta.bg_col = buffer_peek(_buf, 10002, buffer_u8) & 0xF;
    } else if (!variable_struct_exists(_asset.meta, "bg_col")) {
        _asset.meta.bg_col = 0;
    }

    // ── COLLISION TAG GRID ──
    // 40x25 char cells, one byte each: 0 = none, 1..16 = collision type.
    // Same layout regardless of MC/HiRes — this rides on the 1000-entry
    // screen-RAM-sized grid, not on the pixel format.
    if (!variable_struct_exists(_asset.meta, "coll_types")) {
        _asset.meta.coll_types = array_create(1000, 0);
    }
    if (!is_array(_asset.meta.coll_types) || array_length(_asset.meta.coll_types) != 1000) {
        _asset.meta.coll_types = array_create(1000, 0);
    }

    // ── DISK CACHE ──
    // The decoded 320x200 picture is kept on disk, named by the MD5 of the
    // asset's bytes, so a project that opens again (or a surface lost to a
    // window change) uploads it instead of decoding 64000 pixels in GML.
    // The paint data (bg_mask, HiRes role arrays) is only needed by the
    // bitmap editor; it is built on first use by scr_asset_bmp_ensure_decoded.
    var _ckey = scr_asset_bmp_cache_key(_asset);
    if (!_full) {
        var _cached = scr_asset_bmp_cache_load(_ckey);
        if (_cached != -1) {
            _asset.meta.preview_surf = surface_create(320, 200);
            buffer_set_surface(_cached, _asset.meta.preview_surf, 0);
            buffer_delete(_cached);
            _asset.meta.has_data = true;
            if ((_asset.meta[$ "decoded_key"] ?? "") != _ckey) _asset.meta.decode_pending = true;
            return;
        }
    }

// Build a raw RGBA buffer and blast it directly — no draw_point clipping issues
    var _surf_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);

    // Pre-cache all 16 pepto colours as PACKED little-endian RGBA words.
    // One buffer_u32 poke replaces four buffer_u8 pokes per pixel, which is
    // 64000 writes per bitmap instead of 256000. On a 60-frame REU animation
    // that is the difference between a load you wait through and one you do
    // not. _pr/_pg/_pb are kept because the HiRes role-mask seeding and any
    // external caller may still want the components.
    var _pr = array_create(16, 0);
    var _pg = array_create(16, 0);
    var _pb = array_create(16, 0);
    var _pu = array_create(16, 0);
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pr[_c] = color_get_red(_col);
        _pg[_c] = color_get_green(_col);
        _pb[_c] = color_get_blue(_col);
        _pu[_c] = _pr[_c] | (_pg[_c] << 8) | (_pb[_c] << 16) | (255 << 24);
    }

    // bg_mask is built INLINE below rather than by reading the finished
    // surface back off the GPU. The old MC path uploaded the buffer, pulled
    // all 256KB back with buffer_get_surface(), then compared each pixel's
    // RGB against the background RGB — a full pipeline stall plus 192000
    // buffer_peek calls, purely to recover a fact the decoder already knew.
    // Pepto indices map 1:1 to distinct colours, so "_ci equals _bg" is
    // exactly the same test as "these three bytes match", with no readback.
    var _mask = array_create(64000, 0);

    if (!_is_hires) {
        // ── MULTICOLOUR DECODE — 2 bits/pixel, 4 colours/cell, 160 MC px wide ──
        var _bg = _asset.meta.bg_col;
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            var _row_base  = _py * 320;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _col_byte = buffer_peek(_buf, 9002 + _cell, buffer_u8) & 0xF;
                var _c1       = _scr >> 4;
                var _c2       = _scr & 0xF;
                for (var _bp = 0; _bp < 4; _bp++) {
                    var _val = (_bmp_byte >> (6 - _bp * 2)) & 0x3;
                    var _ci  = _bg;
                    if (_val == 1) {
                        _ci = _c1;
                    } else if (_val == 2) {
                        _ci = _c2;
                    } else if (_val == 3) {
                        _ci = _col_byte;
                    }
                    var _is_bg = 1;
                    if (_ci == _bg) {
                        _is_bg = 0;
                    }
                    // Each MC pixel = 2 screen pixels wide in 320px space
                    var _screen_x = (_cx * 4 + _bp) * 2;
                    var _pix      = _row_base + _screen_x;
                    var _word     = _pu[_ci];
                    buffer_poke(_surf_buf, _pix * 4,       buffer_u32, _word);
                    buffer_poke(_surf_buf, (_pix + 1) * 4, buffer_u32, _word);
                    _mask[_pix]     = _is_bg;
                    _mask[_pix + 1] = _is_bg;
                }
            }
        }
   } else {
        // ── HIRES DECODE — 1 bit/pixel, 2 colours/cell, full 320px wide ──
        // Screen RAM byte per cell: high nibble = FG (bit=1), low nibble = BG (bit=0).
        // The file already stores exactly the role model's data (per-cell fg/bg
        // colour + per-pixel bit), so seed hr_role_mask/hr_cell_fg_col/hr_cell_bg_col
        // straight from it here — this is what keeps a loaded/rebuilt HiRes asset's
        // colour-editing behaviour correct without a separate bootstrap pass.
        // bg_mask for HiRes is the raw bit value, which this same pass already
        // has in hand, so the old second 64000-pixel re-walk is gone too.
        var _role = array_create(64000, 0);
        var _fg_cols = array_create(1000, 0);
        var _bg_cols = array_create(1000, 0);
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            var _row_base  = _py * 320;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _fg       = _scr >> 4;
                var _bg_cell  = _scr & 0xF;
                _fg_cols[_cell] = _fg;
                _bg_cols[_cell] = _bg_cell;
                for (var _bp = 0; _bp < 8; _bp++) {
                    var _bit = (_bmp_byte >> (7 - _bp)) & 0x1;
                    var _ci  = _bg_cell;
                    if (_bit == 1) {
                        _ci = _fg;
                    }
                    var _pix = _row_base + _cx * 8 + _bp;
                    buffer_poke(_surf_buf, _pix * 4, buffer_u32, _pu[_ci]);
                    _role[_pix] = _bit;
                    _mask[_pix] = _bit;
                }
            }
        }
        _asset.meta.hr_role_mask   = _role;
        _asset.meta.hr_cell_fg_col = _fg_cols;
        _asset.meta.hr_cell_bg_col = _bg_cols;
    }
    
_asset.meta.preview_surf = surface_create(320, 200);
    buffer_set_surface(_surf_buf, _asset.meta.preview_surf, 0);
    scr_asset_bmp_cache_save(_ckey, _surf_buf);
    buffer_delete(_surf_buf);
    _asset.meta.has_data = true;

    _asset.meta.bg_mask = _mask;
    _asset.meta.needs_mask_init = false;
    _asset.meta.decode_pending  = false;
    _asset.meta.decoded_key     = _ckey;
}

/// Before anything reads bg_mask / the HiRes role arrays: a preview that came
/// from the disk cache has the picture only, so decode it fully once.
function scr_asset_bmp_ensure_decoded(_asset) {
    if (!is_struct(_asset) || !is_struct(_asset.meta)) return;
    if (_asset.meta[$ "decode_pending"] == true) scr_asset_bmp_build_preview(_asset, true);
}

/// Cache file name for this asset's current bytes and pixel format.
function scr_asset_bmp_cache_key(_asset) {
    var _b = _asset.buffer;
    return buffer_md5(_b, 0, buffer_get_size(_b)) + (scr_asset_bmp_is_hires(_asset) ? "_hr" : "_mc");
}

function scr_asset_bmp_cache_dir() {
    return working_directory + "cache/bmp/";
}

/// The cached 320x200 RGBA picture as a new buffer, or -1.
function scr_asset_bmp_cache_load(_key) {
    var _path = scr_asset_bmp_cache_dir() + _key + ".bin";
    if (!file_exists(_path)) return -1;
    var _z = buffer_load(_path);
    if (_z == -1) return -1;
    var _raw = buffer_decompress(_z);
    buffer_delete(_z);
    if (!buffer_exists(_raw)) return -1;
    if (buffer_get_size(_raw) < 320 * 200 * 4) { buffer_delete(_raw); return -1; }
    return _raw;
}

function scr_asset_bmp_cache_save(_key, _rgba) {
    var _dir = scr_asset_bmp_cache_dir();
    if (!directory_exists(_dir)) directory_create(_dir);
    var _path = _dir + _key + ".bin";
    if (file_exists(_path)) return;
    var _z = buffer_compress(_rgba, 0, 320 * 200 * 4);
    buffer_save(_z, _path);
    buffer_delete(_z);
}

// =====================================================================
// BITMAP SPRITE OVERLAY
// Hardware sprites laid over a BITMAP asset in its editor, painted in a
// mode of their own and transferred to a SPRITE_SET when done.
//
// Each sprite has its own X and Y. The VIC shows at most 8 sprites on any
// raster line, so the panel warns (and the canvas marks the lines in red)
// where more than 8 overlap. SETUP NODES / TRANSFER group the sprites into
// 21-line bands by Y (scr_bmp_spr_sorted_rows) for the multiplexer.
// Colours follow the VIC: MC1 / MC2 shared by all sprites, one colour per
// sprite, HiRes or multicolour per sprite. Sprites always draw in front.
//
// meta.spr_overlay (saved with the asset):
//   { version: 2, show, mc1, mc2, mux_nodes, sprites: [ { x, y, col, mc, px[504] } ] }
// (version 1 kept rows: [ { y, sprites } ] - scr_bmp_spr_migrate flattens it)
// px holds one code per pixel (24 x 21): 0 transparent, 1 MC1, 2 sprite
// colour, 3 MC2 — the same values as the sprite bit pairs. A multicolour
// sprite keeps both pixels of a pair equal. HiRes uses 0 / 2 only.
// Runtime (not saved): spr_mode, spr_pen, spr_sel,
// spr_ovl_surf / spr_ovl_ver / spr_ovl_built, spr_undo / spr_redo, drag state.
// =====================================================================
#macro BSO_PER_LINE 8
#macro BSO_MAX      64

function scr_bmp_spr_get(_asset) {
    var _m = _asset.meta;
    if (!variable_struct_exists(_m, "spr_overlay") || !is_struct(_m.spr_overlay)) {
        _m.spr_overlay = { version: 2, show: true, mc1: 1, mc2: 2, sprites: [], mux_nodes: false };
    }
    // Overlays from before free sprites / the MUX option
    if (!variable_struct_exists(_m.spr_overlay, "sprites") || !variable_struct_exists(_m.spr_overlay, "mux_nodes")) {
        var _mig = scr_bmp_spr_migrate(_m.spr_overlay);
        if (is_undefined(_mig)) {
            _mig = { version: 2, show: true, mc1: 1, mc2: 2, sprites: [], mux_nodes: false };
        }
        _m.spr_overlay = _mig;
    }
    if (!variable_struct_exists(_m, "spr_undo")) { _m.spr_undo = []; _m.spr_redo = []; _m.spr_sel = -1; }
    return _m.spr_overlay;
}

/// A saved overlay brought up to version 2 (free sprites), or undefined when
/// it is malformed. Also used by scr_load_workspace_from_path.
function scr_bmp_spr_migrate(_so) {
    if (!is_struct(_so)) {
        return undefined;
    }
    var _list = [];
    if (is_array(_so[$ "sprites"])) {
        _list = _so.sprites;
    } else if (is_array(_so[$ "rows"])) {
        for (var _r = 0; _r < array_length(_so.rows); _r++) {
            var _row = _so.rows[_r];
            if (!is_struct(_row) || !is_array(_row[$ "sprites"])) {
                return undefined;
            }
            for (var _s = 0; _s < array_length(_row.sprites); _s++) {
                var _rs = _row.sprites[_s];
                if (is_struct(_rs)) {
                    _rs.y = _row[$ "y"] ?? 0;
                }
                array_push(_list, _rs);
            }
        }
    }
    var _out = [];
    for (var _i = 0; _i < array_length(_list); _i++) {
        var _sp = _list[_i];
        if (!is_struct(_sp) || !is_array(_sp[$ "px"]) || array_length(_sp.px) != 504) {
            return undefined;
        }
        array_push(_out, { x: _sp[$ "x"] ?? 0, y: _sp[$ "y"] ?? 0, col: _sp[$ "col"] ?? 1, mc: _sp[$ "mc"] ?? 0, px: _sp.px });
    }
    return { version: 2, show: _so[$ "show"] ?? true, mc1: _so[$ "mc1"] ?? 1, mc2: _so[$ "mc2"] ?? 2,
             sprites: _out, mux_nodes: _so[$ "mux_nodes"] ?? false, gen_org: _so[$ "gen_org"] ?? -1 };
}

/// Something about the sprites changed: the overlay image is redrawn.
function scr_bmp_spr_touch(_asset) {
    _asset.meta.spr_ovl_ver = (_asset.meta[$ "spr_ovl_ver"] ?? 0) + 1;
}

function scr_bmp_spr_count(_o) {
    return array_length(_o.sprites);
}

/// Sprites on each of the 200 bitmap lines.
function scr_bmp_spr_line_counts(_o) {
    var _lc = array_create(200, 0);
    for (var _i = 0; _i < array_length(_o.sprites); _i++) {
        var _sy = _o.sprites[_i].y;
        for (var _l = max(0, _sy); _l < min(200, _sy + 21); _l++) {
            _lc[_l] += 1;
        }
    }
    return _lc;
}

/// First bitmap line with more than 8 sprites on it, or -1.
function scr_bmp_spr_overloaded_line(_o) {
    var _lc = scr_bmp_spr_line_counts(_o);
    for (var _l = 0; _l < 200; _l++) {
        if (_lc[_l] > BSO_PER_LINE) {
            return _l;
        }
    }
    return -1;
}

/// The selected sprite struct, or undefined.
function scr_bmp_spr_selected(_asset) {
    var _o = scr_bmp_spr_get(_asset);
    var _s = _asset.meta.spr_sel;
    if (_s < 0 || _s >= array_length(_o.sprites)) return undefined;
    return _o.sprites[_s];
}

function scr_bmp_spr_push_undo(_asset) {
    var _m = _asset.meta;
    array_push(_m.spr_undo, variable_clone(scr_bmp_spr_get(_asset)));
    if (array_length(_m.spr_undo) > 30) array_delete(_m.spr_undo, 0, 1);
    _m.spr_redo = [];
}

/// The overlay as a 320x200 surface (rebuilt only when it changed).
function scr_bmp_spr_surface(_asset) {
    var _m   = _asset.meta;
    var _o   = scr_bmp_spr_get(_asset);
    var _ver = _m[$ "spr_ovl_ver"] ?? 0;
    var _srf = _m[$ "spr_ovl_surf"] ?? -1;
    if (surface_exists(_srf) && (_m[$ "spr_ovl_built"] ?? -1) == _ver) return _srf;
    if (!surface_exists(_srf)) { _srf = surface_create(320, 200); _m.spr_ovl_surf = _srf; }

    var _pu = array_create(16, 0);
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pu[_c] = color_get_red(_col) | (color_get_green(_col) << 8) | (color_get_blue(_col) << 16) | (255 << 24);
    }
    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_fill(_buf, 0, buffer_u32, 0, 320 * 200 * 4);
    for (var _s = 0; _s < array_length(_o.sprites); _s++) {
        var _sp  = _o.sprites[_s];
        var _pen = [0, _pu[_o.mc1 & 15], _pu[_sp.col & 15], _pu[_o.mc2 & 15]];
        for (var _py = 0; _py < 21; _py++) {
            var _yy = _sp.y + _py;
            if (_yy < 0 || _yy >= 200) continue;
            for (var _px = 0; _px < 24; _px++) {
                var _code = _sp.px[_py * 24 + _px];
                if (_code == 0) continue;
                if (!_sp.mc) _code = 2;
                var _xx = _sp.x + _px;
                if (_xx < 0 || _xx >= 320) continue;
                buffer_poke(_buf, (_yy * 320 + _xx) * 4, buffer_u32, _pen[_code]);
            }
        }
    }
    buffer_set_surface(_buf, _srf, 0);
    buffer_delete(_buf);
    _m.spr_ovl_built = _ver;
    return _srf;
}

/// Bitmap pixel -> GUI position, matching the canvas blit.
function scr_bmp_spr_map(_asset, _sx, _sy, _sw, _sh, _zoom_cap) {
    var _m = _asset.meta;
    if (_m.bmp_zoom <= _zoom_cap) return { sx: _sx, sy: _sy, ox: 0, oy: 0, kx: _sw / 320, ky: _sh / 200 };
    var _pz = _m.bmp_zoom / _zoom_cap;
    var _w  = max(1, 320 / _pz);
    var _h  = max(1, 200 / _pz);
    return { sx: _sx, sy: _sy, ox: clamp(_m.bmp_pan_x, 0, 320 - _w), oy: clamp(_m.bmp_pan_y, 0, 200 - _h),
             kx: _sw / _w, ky: _sh / _h };
}

/// Drawn right after the bitmap canvas, inside its scissor.
function scr_bmp_spr_draw(_asset, _sx, _sy, _sw, _sh, _zoom_cap) {
    if (!variable_struct_exists(_asset.meta, "spr_overlay") && !(_asset.meta[$ "spr_mode"] ?? false)) return;
    var _o = scr_bmp_spr_get(_asset);
    var _mp = scr_bmp_spr_map(_asset, _sx, _sy, _sw, _sh, _zoom_cap);
    if (_o.show && array_length(_o.sprites) > 0) {
        var _srf = scr_bmp_spr_surface(_asset);
        draw_surface_part_ext(_srf, _mp.ox, _mp.oy, _sw / _mp.kx, _sh / _mp.ky, _sx, _sy, _mp.kx, _mp.ky, c_white, 1);
    }
    if (!(_asset.meta[$ "spr_mode"] ?? false)) return;
    // Sprite mode: lines with more than 8 sprites in red, then each sprite's box
    var _lc = scr_bmp_spr_line_counts(_o);
    draw_set_alpha(0.35);
    draw_set_color(c_red);
    for (var _l = 0; _l < 200; _l++) {
        if (_lc[_l] > BSO_PER_LINE) {
            var _ly1 = _mp.sy + (_l - _mp.oy) * _mp.ky;
            draw_rectangle(_sx, _ly1, _sx + _sw, _ly1 + _mp.ky, false);
        }
    }
    draw_set_alpha(1);
    var _sel = _asset.meta.spr_sel;
    for (var _s = 0; _s < array_length(_o.sprites); _s++) {
        var _sp = _o.sprites[_s];
        var _x1 = _mp.sx + (_sp.x - _mp.ox) * _mp.kx;
        var _x2 = _mp.sx + (_sp.x + 24 - _mp.ox) * _mp.kx;
        var _y1 = _mp.sy + (_sp.y - _mp.oy) * _mp.ky;
        var _y2 = _mp.sy + (_sp.y + 21 - _mp.oy) * _mp.ky;
        if (_s == _sel) {
            draw_set_color(c_yellow);
            draw_rectangle(_x1, _y1, _x2, _y2, true);
            draw_rectangle(_x1 - 1, _y1 - 1, _x2 + 1, _y2 + 1, true);
        } else {
            draw_set_color(make_color_rgb(80, 220, 255));
            draw_rectangle(_x1, _y1, _x2, _y2, true);
        }
    }
}

/// Index of the topmost sprite under bitmap pixel (_px, _py), or -1.
function scr_bmp_spr_hit(_o, _px, _py) {
    for (var _s = array_length(_o.sprites) - 1; _s >= 0; _s--) {
        var _sp = _o.sprites[_s];
        if (_px >= _sp.x && _px < _sp.x + 24 && _py >= _sp.y && _py < _sp.y + 21) return _s;
    }
    return -1;
}

/// Sprite paint mode input, from the bitmap editor. Returns true while
/// sprite mode is on, so the bitmap tools stand down.
function scr_bmp_spr_edit(_asset, _raw_px, _raw_py, _in_bounds) {
    var _m = _asset.meta;
    if (!(_m[$ "spr_mode"] ?? false)) return false;
    var _o   = scr_bmp_spr_get(_asset);
    var _pen = _m[$ "spr_pen"] ?? "SPR";

    // A palette click recolours what the pen paints with
    var _ac = _m[$ "active_color"] ?? 1;
    if ((_m[$ "spr_last_col"] ?? _ac) != _ac) {
        var _sel = scr_bmp_spr_selected(_asset);
        scr_bmp_spr_push_undo(_asset);
        if (_pen == "MC1") _o.mc1 = _ac;
        else if (_pen == "MC2") _o.mc2 = _ac;
        else if (!is_undefined(_sel)) _sel.col = _ac;
        scr_bmp_spr_touch(_asset);
    }
    _m.spr_last_col = _ac;

    // Undo / redo of the sprite layer
    if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z")) && array_length(_m.spr_undo) > 0) {
        array_push(_m.spr_redo, variable_clone(_o));
        _m.spr_overlay = array_pop(_m.spr_undo);
        scr_bmp_spr_touch(_asset);
        return true;
    }
    if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Y")) && array_length(_m.spr_redo) > 0) {
        array_push(_m.spr_undo, variable_clone(_o));
        _m.spr_overlay = array_pop(_m.spr_redo);
        scr_bmp_spr_touch(_asset);
        return true;
    }

    var _lmb = mouse_check_button(mb_left);
    var _rmb = mouse_check_button(mb_right);
    if (!_lmb && !_rmb) { _m.spr_painting = false; _m.spr_dragging = false; return true; }

    var _pressed = (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right))
                && _in_bounds && !global.ui_click_consumed && !global.any_picker_open;
    if (_pressed) {
        var _hit = scr_bmp_spr_hit(_o, _raw_px, _raw_py);
        if (_hit < 0) return true;
        _m.spr_sel = _hit;
        // A HiRes sprite has no MC1 / MC2 to paint with
        if (!_o.sprites[_hit].mc && (_pen == "MC1" || _pen == "MC2")) {
            _pen = "SPR";
            _m.spr_pen = "SPR";
        }
        scr_bmp_spr_sync_palette(_asset);
        scr_bmp_spr_push_undo(_asset);
        _o = _m.spr_overlay;
        var _sp0 = _o.sprites[_hit];
        if (_pen == "MOVE" && _lmb) {
            _m.spr_dragging = true;
            _m.spr_drag_mx = _raw_px;
            _m.spr_drag_my = _raw_py;
            _m.spr_drag_x0 = _sp0.x;
            _m.spr_drag_y0 = _sp0.y;
        } else {
            _m.spr_painting = true;
        }
        global.ui_click_consumed = true;
    }

    var _sp = scr_bmp_spr_selected(_asset);
    if (is_undefined(_sp)) return true;

    if (_m[$ "spr_dragging"] ?? false) {
        // Free X and Y; the panel warns when a line ends up with more than 8
        _sp.x = clamp(_m.spr_drag_x0 + (_raw_px - _m.spr_drag_mx), -23, 319);
        _sp.y = clamp(_m.spr_drag_y0 + (_raw_py - _m.spr_drag_my), -20, 199);
        scr_bmp_spr_touch(_asset);
    } else if ((_m[$ "spr_painting"] ?? false) && _in_bounds) {
        var _lx = _raw_px - _sp.x;
        var _ly = _raw_py - _sp.y;
        if (_lx >= 0 && _lx < 24 && _ly >= 0 && _ly < 21) {
            var _code = 2;
            if (_rmb || _pen == "ERASE") _code = 0;
            else if (_pen == "MC1") _code = 1;
            else if (_pen == "MC2") _code = 3;
            if (!_sp.mc && _code != 0) _code = 2;   // HiRes: one colour only
            if (_sp.mc) {
                _lx -= _lx mod 2;
                _sp.px[_ly * 24 + _lx]     = _code;
                _sp.px[_ly * 24 + _lx + 1] = _code;
            } else {
                _sp.px[_ly * 24 + _lx] = _code;
            }
            scr_bmp_spr_touch(_asset);
        }
    }
    return true;
}

/// Left-column panel of the bitmap editor (edit mode). _y = top of the panel.
function scr_bmp_spr_panel(_asset, _x, _y, _mx, _my) {
    var _m  = _asset.meta;
    var _o  = scr_bmp_spr_get(_asset);
    var _w  = 110;
    var _on = _m[$ "spr_mode"] ?? false;
    var _click = mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open;
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);

    // S toggles the paint target (Ctrl+S stays SAVE)
    if (keyboard_check_pressed(ord("S")) && !keyboard_check(vk_control)) {
        _on = !_on;
        _m.spr_mode = _on;
        if (_on) scr_bmp_spr_default_row(_asset);
    }

    draw_set_color(make_color_rgb(80, 220, 255));
    draw_text_l(_x, _y, "SPRITES  " + string(scr_bmp_spr_count(_o)) + "/64");
    _y += 16;

    // Button: label, colour when active, returns clicked
    var _btn = function(_bx, _by, _bw, _txt, _active, _mx, _my, _click) {
        var _hov = point_in_rectangle(_mx, _my, _bx, _by, _bx + _bw, _by + 16);
        draw_set_color(_active ? make_color_rgb(40, 120, 160) : (_hov ? make_color_rgb(70, 70, 90) : make_color_rgb(35, 35, 50)));
        draw_rectangle(_bx, _by, _bx + _bw, _by + 16, false);
        draw_set_color(_hov ? c_white : c_ltgray);
        draw_rectangle(_bx, _by, _bx + _bw, _by + 16, true);
        draw_set_halign(fa_center);
        draw_text_l(_bx + _bw * 0.5, _by + 1, _txt);
        draw_set_halign(fa_left);
        return _hov && _click;
    };

    if (_btn(_x, _y, _w, _on ? "PAINT: SPRITES" : "PAINT: BITMAP", _on, _mx, _my, _click)) {
        _m.spr_mode = !_on; _on = !_on; global.ui_click_consumed = true;
        if (_on) scr_bmp_spr_default_row(_asset);
    }
    _y += 20;
    if (_btn(_x, _y, _w, _o.show ? "SPRITES: SHOW" : "SPRITES: HIDE", _o.show, _mx, _my, _click)) {
        _o.show = !_o.show; scr_bmp_spr_touch(_asset); global.ui_click_consumed = true;
    }
    _y += 20;
    // How SETUP NODES builds the multiplexer (more than one row): one commented
    // MACRO_CODE block, or VWAIT + MACRO_SPR nodes per band
    var _mux_lbl = "MUX: CODE";
    if (_o.mux_nodes) {
        _mux_lbl = "MUX: NODES";
    }
    if (_btn(_x, _y, _w, _mux_lbl, false, _mx, _my, _click)) {
        _o.mux_nodes = !_o.mux_nodes; global.ui_click_consumed = true;
    }
    _y += 20;
    // A callable program for this bitmap and its sprites (scr_bmp_spr_setup_nodes)
    if (_btn(_x, _y, _w, "SETUP NODES", false, _mx, _my, _click)) {
        global.ui_click_consumed = true;
        scr_bmp_spr_setup_nodes(_asset);
    }
    _y += 20;
    if (!_on) return;

    // Tools: ERASE / MOVE. Painting colours are picked from the swatches below.
    var _pen = _m[$ "spr_pen"] ?? "SPR";
    if (_btn(_x, _y, 52, "ERASE", _pen == "ERASE", _mx, _my, _click)) {
        _m.spr_pen = "ERASE"; global.ui_click_consumed = true;
    }
    if (_btn(_x + 56, _y, 52, "MOVE", _pen == "MOVE", _mx, _my, _click)) {
        _m.spr_pen = "MOVE"; global.ui_click_consumed = true;
    }
    _y += 20;

    // Add / delete. A new sprite goes right of the selected one (same Y).
    var _sel = scr_bmp_spr_selected(_asset);
    if (scr_bmp_spr_count(_o) < BSO_MAX && _btn(_x, _y, 52, "+ SPR", false, _mx, _my, _click)) {
        scr_bmp_spr_push_undo(_asset); _o = _m.spr_overlay;
        var _nx = 0;
        var _ny = 0;
        var _nmc = 0;
        if (!is_undefined(_sel)) {
            _nx = min(_sel.x + 24, 296);
            _ny = _sel.y;
            _nmc = _sel.mc;
        }
        array_push(_o.sprites, { x: _nx, y: _ny, col: _m[$ "active_color"] ?? 1, mc: _nmc, px: array_create(504, 0) });
        _m.spr_sel = array_length(_o.sprites) - 1;
        scr_bmp_spr_touch(_asset); global.ui_click_consumed = true;
    }
    if (!is_undefined(_sel) && _btn(_x + 56, _y, 52, "DEL SPR", false, _mx, _my, _click)) {
        scr_bmp_spr_push_undo(_asset); _o = _m.spr_overlay;
        array_delete(_o.sprites, _m.spr_sel, 1);
        _m.spr_sel = -1;
        scr_bmp_spr_touch(_asset); global.ui_click_consumed = true;
    }
    _y += 20;

    _sel = scr_bmp_spr_selected(_asset);
    if (!is_undefined(_sel)) {
        if (_btn(_x, _y, 52, _sel.mc ? "MC" : "HIRES", _sel.mc, _mx, _my, _click)) {
            scr_bmp_spr_push_undo(_asset); _o = _m.spr_overlay; _sel = scr_bmp_spr_selected(_asset);
            _sel.mc = _sel.mc ? 0 : 1;
            for (var _p = 0; _p < 504; _p++) {
                if (_sel.mc) { if (_p mod 2 == 1) _sel.px[_p] = _sel.px[_p - 1]; }   // pairs follow the left pixel
                else if (_sel.px[_p] != 0) _sel.px[_p] = 2;
            }
            scr_bmp_spr_touch(_asset); global.ui_click_consumed = true;
        }
        draw_set_color(c_ltgray);
        draw_text_l(_x + 56, _y + 1, "S" + string(_m.spr_sel));
        _y += 20;
        draw_text_l(_x, _y, "X" + string(_sel.x) + "  Y" + string(_sel.y));
        _y += 16;
    }

    // More than 8 sprites on one raster line can't be shown (red on the canvas)
    var _ovl = scr_bmp_spr_overloaded_line(_o);
    if (_ovl >= 0) {
        draw_set_color(c_red);
        draw_text_l(_x, _y, "OVER 8 ON LINE " + string(_ovl));
        _y += 12;
        draw_text_l(_x, _y, "MOVE ONE DOWN, PAST");
        _y += 12;
        draw_text_l(_x, _y, "THE OTHERS + A GAP");
        _y += 16;
    }

    // Colours: click a swatch to paint with it, or a strip colour to set it
    // (and paint with it). SPR is the selected sprite's own colour; MC1 / MC2
    // are shared by all sprites and unused (greyed) on a HiRes sprite.
    var _hires = false;
    if (!is_undefined(_sel)) {
        _hires = !_sel.mc;
    }
    if (_hires && (_pen == "MC1" || _pen == "MC2")) {
        _pen = "SPR"; _m.spr_pen = "SPR"; scr_bmp_spr_sync_palette(_asset);
    }
    var _cols = [ is_undefined(_sel) ? -1 : _sel.col, _o.mc1, _o.mc2 ];
    var _lbls = ["SPR", "MC1", "MC2"];
    for (var _i = 0; _i < 3; _i++) {
        var _cx = _x + _i * 37;
        var _off = (_i > 0 && _hires);
        var _live = (_cols[_i] >= 0 && !_off);
        var _is_pen = (_pen == _lbls[_i]);
        draw_set_color(c_ltgray);
        if (_off) {
            draw_set_color(make_color_rgb(70, 70, 80));
        }
        draw_text_l(_cx, _y, _lbls[_i]);
        if (_cols[_i] >= 0) {
            draw_set_color(scr_c64_pepto_colour(_cols[_i]));
            if (_off) {
                draw_set_color(make_color_rgb(45, 45, 55));
            }
            draw_rectangle(_cx, _y + 12, _cx + 30, _y + 24, false);
        }
        var _sw_hov = _live && point_in_rectangle(_mx, _my, _cx, _y + 12, _cx + 30, _y + 24);
        if (_is_pen && _live) {
            draw_set_color(c_yellow);
            draw_rectangle(_cx - 1, _y + 11, _cx + 31, _y + 25, true);
        } else if (_sw_hov) {
            draw_set_color(c_white);
            draw_rectangle(_cx, _y + 12, _cx + 30, _y + 24, true);
        } else {
            draw_set_color(c_gray);
            draw_rectangle(_cx, _y + 12, _cx + 30, _y + 24, true);
        }
        if (_sw_hov && _click) {
            _m.spr_pen = _lbls[_i]; _pen = _lbls[_i];
            scr_bmp_spr_sync_palette(_asset);
            global.ui_click_consumed = true;
        }

        // Palette strip under the swatch
        if (_cols[_i] >= 0) {
            var _sy0 = _y + 28;
            for (var _c = 0; _c < 16; _c++) {
                var _cy1 = _sy0 + _c * 8;
                var _cy2 = _cy1 + 7;
                draw_set_color(scr_c64_pepto_colour(_c));
                draw_rectangle(_cx, _cy1, _cx + 30, _cy2, false);
                if (_off) {
                    draw_set_alpha(0.75);
                    draw_set_color(make_color_rgb(18, 18, 28));
                    draw_rectangle(_cx, _cy1, _cx + 30, _cy2, false);
                    draw_set_alpha(1);
                    continue;
                }
                var _chov = point_in_rectangle(_mx, _my, _cx, _cy1, _cx + 30, _cy2);
                if (_c == _cols[_i]) {
                    draw_set_color(c_white);
                    draw_rectangle(_cx, _cy1, _cx + 30, _cy2, true);
                } else if (_chov) {
                    draw_set_color(c_ltgray);
                    draw_rectangle(_cx, _cy1, _cx + 30, _cy2, true);
                }
                if (_chov && _click) {
                    if (_c != _cols[_i]) {
                        scr_bmp_spr_push_undo(_asset);
                        _o = _m.spr_overlay;
                        if (_i == 0) {
                            var _csel = scr_bmp_spr_selected(_asset);
                            if (!is_undefined(_csel)) {
                                _csel.col = _c;
                            }
                        } else if (_i == 1) {
                            _o.mc1 = _c;
                        } else {
                            _o.mc2 = _c;
                        }
                        scr_bmp_spr_touch(_asset);
                        _cols[_i] = _c;
                    }
                    // This colour is now the one being painted with. Syncing the
                    // main palette stops scr_bmp_spr_edit reading it as a click.
                    _m.spr_pen = _lbls[_i]; _pen = _lbls[_i];
                    scr_bmp_spr_sync_palette(_asset);
                    global.ui_click_consumed = true;
                }
            }
        }
    }
    _y += 32 + 132;

    // Transfer to a SPRITE_SET: cycle the target, then send
    var _targets = ["NEW SET"];
    var _am = obj_asset_manager;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        if (_a.type == "SPRITE_SET") array_push(_targets, _a.name);
    }
    var _ti = clamp(_m[$ "spr_target_idx"] ?? 0, 0, array_length(_targets) - 1);
    var _thov = point_in_rectangle(_mx, _my, _x, _y, _x + _w, _y + 16);
    if (_btn(_x, _y, _w, "TO: " + _targets[_ti], false, _mx, _my, _click)) {
        _ti = (_ti + 1) mod array_length(_targets); global.ui_click_consumed = true;
    }
    if (_thov && mouse_check_button_pressed(mb_right)) _ti = (_ti + array_length(_targets) - 1) mod array_length(_targets);
    _m.spr_target_idx = _ti;
    _y += 20;
    if (_btn(_x, _y, _w, "TRANSFER", false, _mx, _my, _click)) {
        scr_bmp_spr_transfer(_asset, (_ti == 0) ? "" : _targets[_ti]);
        global.ui_click_consumed = true;
    }
}

/// Write the overlay sprites, row by row, into a SPRITE_SET from slot 0.
/// _target_name "" = a new set (named _new_name, or after the bitmap). _addr >= 0
/// also moves the set there. _quiet skips the done message. Returns the set,
/// or undefined when nothing was written.
function scr_bmp_spr_transfer(_asset, _target_name, _quiet = false, _addr = -1, _new_name = "") {
    var _o = scr_bmp_spr_get(_asset);
    var _list = [];
    var _rows = scr_bmp_spr_sorted_rows(_o);
    for (var _r = 0; _r < array_length(_rows); _r++) {
        for (var _s = 0; _s < array_length(_rows[_r].sprites); _s++) {
            if (array_length(_list) < 64) array_push(_list, _rows[_r].sprites[_s]);
        }
    }
    var _n = array_length(_list);
    if (_n == 0) { scr_show_message("TRANSFER SPRITES\n\nThere are no sprites to transfer. Draw on a sprite first (empty ones are skipped)."); return undefined; }

    var _am  = obj_asset_manager;
    var _dst = undefined;
    var _dst_idx = -1;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        if (_a.type == "SPRITE_SET" && _a.name == _target_name && _target_name != "") { _dst = _a; _dst_idx = _ai; break; }
    }
    if (is_undefined(_dst)) {
        var _set_addr = scr_asset_default_address("SPRITE_SET");
        with (obj_c64_node) { if (node_type == "MACRO_BMP" && is_connected) _set_addr = 0x6800; }
        _dst = { type: "SPRITE_SET", name: scr_music_maker_unique_name((_new_name != "") ? _new_name : (string_upper(_asset.name) + "_SPR")),
                 file: "", address: _set_addr, buffer: buffer_create(64, buffer_fixed, 1),
                 meta: { format: "binary", has_colour: true, bg_col: _asset.meta[$ "bg_col"] ?? 0,
                         mc1_col: 1, mc2_col: 2, sprite_mcs: [0], sprite_ucs: [1],
                         spr_sprites: array_create(1, -1), found_count: 0, used_count: 0, total_size: 64 },
                 load_later: false, d64_filename: "", reu_filename: "", reu_size: 0, reu_used: 0,
                 linked_assets: [], group: "" };
        buffer_fill(_dst.buffer, 0, buffer_u8, 0, 64);
        ds_list_add(_am.asset_list, _dst);
    } else if (_am.spred64_v2.active && _am.spred64_v2.asset_index == _dst_idx) {
        scr_show_message("TRANSFER SPRITES\n\nClose the sprite editor on '" + _dst.name + "' first.");
        return undefined;
    }

    // Slots past the transferred ones keep what they had
    var _old_used = (_dst.meta[$ "used_count"] ?? 0);
    var _used = max(_old_used, _n);
    var _buf  = buffer_create(_used * 64, buffer_fixed, 1);
    buffer_fill(_buf, 0, buffer_u8, 0, _used * 64);
    var _old_sz = buffer_exists(_dst.buffer) ? buffer_get_size(_dst.buffer) : 0;
    if (_old_used > _n && _old_sz > _n * 64) {
        buffer_copy(_dst.buffer, _n * 64, min(_old_sz, _used * 64) - _n * 64, _buf, _n * 64);
    }
    var _mcs = array_create(_used, 0);
    var _ucs = array_create(_used, 1);
    for (var _i = _n; _i < _used; _i++) {
        if (is_array(_dst.meta[$ "sprite_mcs"]) && _i < array_length(_dst.meta.sprite_mcs)) _mcs[_i] = _dst.meta.sprite_mcs[_i];
        if (is_array(_dst.meta[$ "sprite_ucs"]) && _i < array_length(_dst.meta.sprite_ucs)) _ucs[_i] = _dst.meta.sprite_ucs[_i];
    }
    for (var _i = 0; _i < _n; _i++) {
        var _sp = _list[_i];
        _mcs[_i] = _sp.mc ? 1 : 0;
        _ucs[_i] = _sp.col & 15;
        for (var _y = 0; _y < 21; _y++) {
            for (var _b = 0; _b < 3; _b++) {
                var _v = 0;
                if (_sp.mc) {
                    // 4 double-wide pixels per byte: the pixel code is the bit pair
                    for (var _p = 0; _p < 4; _p++) _v |= (_sp.px[_y * 24 + _b * 8 + _p * 2] & 3) << (6 - _p * 2);
                } else {
                    for (var _p = 0; _p < 8; _p++) if (_sp.px[_y * 24 + _b * 8 + _p] != 0) _v |= (128 >> _p);
                }
                buffer_poke(_buf, _i * 64 + _y * 3 + _b, buffer_u8, _v);
            }
        }
    }
    if (buffer_exists(_dst.buffer)) buffer_delete(_dst.buffer);
    _dst.buffer = _buf;
    _dst.meta.sprite_mcs  = _mcs;
    _dst.meta.sprite_ucs  = _ucs;
    _dst.meta.mc1_col     = _o.mc1 & 15;
    _dst.meta.mc2_col     = _o.mc2 & 15;
    _dst.meta.used_count  = _used;
    _dst.meta.found_count = _used;
    _dst.meta.total_size  = _used * 64;
    _dst.meta.has_colour  = true;
    if (_addr >= 0) _dst.address = _addr;
    scr_asset_spr_cache_sprites(_dst, true);

    global.memory_bar_dirty = true;
    global.addresses_dirty  = true;
    global.undo_dirty       = true;
    with (obj_workspace_manager) { alarm[3] = 6; }
    if (!_quiet) scr_show_message("TRANSFER SPRITES\n\n" + string(_n) + " sprite(s) written to '" + _dst.name
        + "', slots 0-" + string(_n - 1) + " (row by row, top to bottom).");
    return _dst;
}

/// Show the colour the current pen paints with in the palette, so the next
/// palette click is always a change (scr_bmp_spr_edit applies it).
function scr_bmp_spr_sync_palette(_asset) {
    var _m   = _asset.meta;
    var _o   = scr_bmp_spr_get(_asset);
    var _pen = _m[$ "spr_pen"] ?? "SPR";
    var _c   = -1;
    if (_pen == "MC1") _c = _o.mc1;
    else if (_pen == "MC2") _c = _o.mc2;
    else {
        var _sel = scr_bmp_spr_selected(_asset);
        if (!is_undefined(_sel)) _c = _sel.col;
    }
    if (_c >= 0) { _m.active_color = _c; _m.spr_last_col = _c; }
}

/// Entering sprite mode with no sprites yet: one sprite at the top left, so
/// there is something to paint on straight away (+ SPR adds more).
function scr_bmp_spr_default_row(_asset) {
    var _o = scr_bmp_spr_get(_asset);
    if (array_length(_o.sprites) > 0) return;
    array_push(_o.sprites, { x: 0, y: 0, col: _asset.meta[$ "active_color"] ?? 1, mc: 0, px: array_create(504, 0) });
    _asset.meta.spr_sel = 0;
    scr_bmp_spr_touch(_asset);
}

// =====================================================================
// SETUP NODES — a ready-to-call program for the bitmap and its sprites
//
// Builds an ORG block (placed in free RAM) holding
//     LABEL <NAME>_SHOW
//     SPR ENABLE (all off) / BITMAP / [ SPRITE x n  when one row ] / RTS
// and, when there is more than one row,
//     LABEL <NAME>_FRAME / CODE (scan-line multiplexer) / RTS
// The sprites go to the SPRITE_SET <NAME>_SPR, placed inside the bitmap's
// VIC bank so the pointers reach them. Running it again replaces the block.
//
// Multiplexer: hardware sprites 0-7 are re-placed for each band. It waits
// on $D012 for the line before the band starts and rewrites Y, X, pointer,
// colour, MSB, MC and enable for that row. Call it once a frame before the
// first band (e.g. right after a VWAIT at the bottom of the screen).
// =====================================================================

/// The drawn-on sprites (empty ones are left out) grouped into 21-line bands
/// by Y, top to bottom - the order SETUP NODES / TRANSFER write the slots in.
function scr_bmp_spr_sorted_rows(_o) {
    var _list = [];
    for (var _s = 0; _s < array_length(_o.sprites); _s++) {
        if (!scr_bmp_spr_is_empty(_o.sprites[_s])) {
            array_push(_list, _o.sprites[_s]);
        }
    }
    array_sort(_list, function(_a, _b) {
        if (_a.y != _b.y) return _a.y - _b.y;
        return _a.x - _b.x;
    });
    // Bands: a band starts at its top sprite and takes the sprites that start
    // within its 21 lines, up to 8 (more than that is an overloaded line,
    // which the editor warns about - the extras spill into the next band).
    var _rows = [];
    var _cur = undefined;
    for (var _i = 0; _i < array_length(_list); _i++) {
        var _sp = _list[_i];
        var _new_band = is_undefined(_cur);
        if (!_new_band) {
            if (_sp.y >= _cur.y + 21 || array_length(_cur.sprites) >= BSO_PER_LINE) {
                _new_band = true;
            }
        }
        if (_new_band) {
            _cur = { y: _sp.y, sprites: [] };
            array_push(_rows, _cur);
        }
        array_push(_cur.sprites, _sp);
    }
    return _rows;
}

/// True when the sprite has no pixels set.
function scr_bmp_spr_is_empty(_sp) {
    for (var _p = 0; _p < 504; _p++) {
        if (_sp.px[_p] != 0) {
            return false;
        }
    }
    return true;
}

function scr_bmp_spr_overlaps(_a1, _a2, _b1, _b2) { return (_a1 < _b2 && _b1 < _a2); }

/// A 64-byte aligned home for _n sprites inside the bitmap's VIC bank,
/// clear of the bitmap / screen / colour block, the VIC's char-ROM shadow
/// and anything else in memory (except the set being replaced). -1 if none.
function scr_bmp_spr_find_spr_addr(_bmp_addr, _n, _ignore_asset) {
    var _rg   = scr_bmp_regions(_bmp_addr);
    var _bb   = _rg.bank_base;
    var _size = _n * 64;
    scr_build_memory_bar_cache();
    for (var _a = _bb; _a + _size <= _bb + 0x4000; _a += 64) {
        var _e = _a + _size;
        if (_a < 0x0800) continue;
        if (scr_bmp_spr_overlaps(_a, _e, _rg.bmp_addr, _rg.bmp_addr + 8000)) continue;
        if (scr_bmp_spr_overlaps(_a, _e, _rg.scr_addr, _rg.scr_addr + 1024)) continue;
        if (scr_bmp_spr_overlaps(_a, _e, _rg.col_addr, _rg.col_addr + 1000)) continue;
        if ((_rg.bank == 0 || _rg.bank == 2) && scr_bmp_spr_overlaps(_a, _e, _bb + 0x1000, _bb + 0x2000)) continue;
        if (scr_bmp_spr_overlaps(_a, _e, 0xD000, 0xE000)) continue;
        var _clash = false;
        for (var _i = 0; _i < array_length(global.memory_bar_segments); _i++) {
            var _s = global.memory_bar_segments[_i];
            if (_s.type == "CODE" && _s.no_conflict) continue;
            if (!is_undefined(_ignore_asset) && _s.addr == _ignore_asset.address) continue;
            if (scr_bmp_spr_overlaps(_a, _e, _s.addr, _s.addr + max(1, _s.size))) { _clash = true; break; }
        }
        if (!_clash) return _a;
    }
    return -1;
}

/// Free RAM the CPU can run code in ($0900-$9FFF, $C000-$CFFF), clear of
/// memory in use and the extra [start, end) ranges given. -1 if none.
function scr_bmp_spr_free_code(_size, _excl) {
    scr_build_memory_bar_cache();
    for (var _a = 0x0900; _a + _size <= 0xD000; _a += 0x40) {
        var _e = _a + _size;
        if (scr_bmp_spr_overlaps(_a, _e, 0xA000, 0xC000)) continue;
        var _ok = true;
        for (var _x = 0; _x < array_length(_excl) && _ok; _x++) {
            if (scr_bmp_spr_overlaps(_a, _e, _excl[_x][0], _excl[_x][1] + 32)) _ok = false;
        }
        for (var _i = 0; _i < array_length(global.memory_bar_segments) && _ok; _i++) {
            var _s = global.memory_bar_segments[_i];
            if (_s.type == "CODE" && _s.no_conflict) continue;
            if (scr_bmp_spr_overlaps(_a, _e, _s.addr, _s.addr + max(1, _s.size) + 32)) _ok = false;
        }
        if (_ok) return _a;
    }
    return -1;
}

function scr_bmp_spr_hex(_v, _d) {
    var _h = string_upper(decimal_to_hex(_v));
    while (string_length(_h) < _d) _h = "0" + _h;
    return "$" + _h;
}

/// The scan-line multiplexer as assembly for a MACRO_CODE block.
function scr_bmp_spr_frame_code(_name, _set, _rows, _o, _scr_addr, _ptr0) {
    var _t = "// @asset " + _set.name + "\n"
           + "// Sprite multiplexer for " + _name + ": re-places hardware sprites 0-7\n"
           + "// for each 21-line band, timed off the raster ($D012). Call once per\n"
           + "// frame before the first band, e.g. right after a VWAIT at the bottom.\n"
           + "; shared multicolours 1 and 2 for all sprites\n"
           + "    lda #" + scr_bmp_spr_hex(_o.mc1 & 15, 2) + "\n    sta $d025\n"
           + "    lda #" + scr_bmp_spr_hex(_o.mc2 & 15, 2) + "\n    sta $d026\n";
    var _slot = 0;
    for (var _r = 0; _r < array_length(_rows); _r++) {
        var _row = _rows[_r];
        var _sp  = _row.sprites;
        var _n   = min(array_length(_sp), 8);
        var _yy  = _row.y + 50;
        if (_r == 0) {
            _t += "; band 0 (raster line " + string(_yy) + "): set straight away - this also moves the\n"
                + "; sprites back up to the top row after the last band of the previous frame\n";
        } else {
            // Wait for the last line before this band, then swap the sprites over
            var _wl = _name + "_W" + string(_r);
            _t += "; band " + string(_r) + " starts on line " + string(_yy) + "\n"
                + "; wait until the raster ($d012) reaches the line before it\n"
                + _wl + ":\n    lda $d012\n    cmp #" + scr_bmp_spr_hex(_yy - 1, 2) + "\n    bcc " + _wl + "\n"
                + "; the previous band is being drawn now, so reuse the 8 hardware sprites for this one\n";
        }
        var _en = 0, _msb = 0, _mc = 0;
        for (var _k = 0; _k < _n; _k++) {
            var _hx = _sp[_k].x + 24;
            _en |= (1 << _k);
            if (_hx > 255) _msb |= (1 << _k);
            if (_sp[_k].mc) _mc |= (1 << _k);
        }
        for (var _k = 0; _k < _n; _k++) {
            var _hx = _sp[_k].x + 24;
            _t += "; sprite " + string(_k) + ": Y, X (low byte), pointer (slot " + string(_slot + _k) + "), colour\n";
            _t += "    lda #" + scr_bmp_spr_hex((_sp[_k].y + 50) & 255, 2) + "\n    sta " + scr_bmp_spr_hex(0xD001 + _k * 2, 4) + "\n"
                + "    lda #" + scr_bmp_spr_hex(_hx & 255, 2) + "\n    sta " + scr_bmp_spr_hex(0xD000 + _k * 2, 4) + "\n"
                + "    lda #" + scr_bmp_spr_hex((_ptr0 + _slot + _k) & 255, 2) + "\n    sta " + scr_bmp_spr_hex(_scr_addr + 0x3F8 + _k, 4) + "\n"
                + "    lda #" + scr_bmp_spr_hex(_sp[_k].col & 15, 2) + "\n    sta " + scr_bmp_spr_hex(0xD027 + _k, 4) + "\n";
        }
        _t += "; X high bits, multicolour bits, then switch on the sprites this band uses\n";
        _t += "    lda #" + scr_bmp_spr_hex(_msb, 2) + "\n    sta $d010\n"
            + "    lda #" + scr_bmp_spr_hex(_mc, 2) + "\n    sta $d01c\n"
            + "    lda #" + scr_bmp_spr_hex(_en, 2) + "\n    sta $d015\n";
        _slot += array_length(_sp);
    }
    return _t;
}

/// Spawn a node of _type with _inst under _parent at (_x, _y).
function scr_bmp_spr_node(_type, _inst, _x, _y, _parent) {
    var _n = scr_node_spawn(_type, _x, _y);
    _n.instructions = _inst;
    _n.is_connected = true;
    _n.org_parent   = _parent;
    with (_n) event_user(0);
    _n.height_dirty = true;
    _n.stats_cache_dirty = true;
    scr_macro_sync_height(_n);
    _n.prev_height = _n.height;
    return _n;
}

function scr_bmp_spr_setup_nodes(_asset) {
    var _o    = scr_bmp_spr_get(_asset);
    var _rows = scr_bmp_spr_sorted_rows(_o);
    var _n    = 0;
    for (var _r = 0; _r < array_length(_rows); _r++) _n += array_length(_rows[_r].sprites);
    _n = min(_n, 64);
    var _init = scr_init_anchor();
    if (!instance_exists(_init)) { scr_show_message("SETUP NODES\n\nThis project has no SYSTEM INIT node."); return; }

    // A name usable as a label
    var _name = string_upper(_asset.name);
    var _clean = "";
    for (var _i = 1; _i <= string_length(_name); _i++) {
        var _ch = string_char_at(_name, _i);
        _clean += (string_pos(_ch, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") > 0) ? _ch : "_";
    }
    if (_clean == "" || string_pos(string_char_at(_clean, 1), "0123456789") > 0) _clean = "BMP_" + _clean;

    // Settle any pending change, then one undo point for the whole setup
    if (global.undo_dirty) scr_c64_do_update_addresses();
    scr_undo_snapshot();
    global.undo_dirty = false;

    // Replace a block made by an earlier SETUP NODES
    var _old_uid = _o[$ "gen_org"] ?? -1;
    if (_old_uid > 0) {
        var _old = noone;
        with (obj_c64_node) { if (node_type == "ORG" && stable_uid == _old_uid) _old = id; }
        if (instance_exists(_old)) {
            with (obj_c64_node) { if (org_parent == _old) instance_destroy(); }
            with (_old) instance_destroy();
        }
    }

    var _bmp_addr = real(_asset.address);
    var _rg = scr_bmp_regions(_bmp_addr);
    var _excl = [[_rg.bmp_addr, _rg.bmp_addr + 8000], [_rg.scr_addr, _rg.scr_addr + 1024], [_rg.col_addr, _rg.col_addr + 1000]];

    // Sprites into <NAME>_SPR, inside the bitmap's VIC bank
    var _set = undefined;
    var _ptr0 = 0;
    if (_n > 0) {
        var _set_name = scr_clamp_asset_name(_clean, 11) + "_SPR";
        var _have = undefined;
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.name == _set_name) _have = _a;
        }
        var _spr_addr = scr_bmp_spr_find_spr_addr(_bmp_addr, max(_n, is_undefined(_have) ? 0 : (_have.meta[$ "used_count"] ?? 0)), _have);
        if (_spr_addr < 0) {
            scr_show_message("SETUP NODES\n\nThere is no room for " + string(_n) + " sprites in VIC bank "
                + string(_rg.bank) + " next to this bitmap.");
            return;
        }
        _set = scr_bmp_spr_transfer(_asset, is_undefined(_have) ? "" : _set_name, true, _spr_addr, _set_name);
        if (is_undefined(_set)) return;
        _ptr0 = (_spr_addr - _rg.bank_base) div 64;
        array_push(_excl, [_spr_addr, _spr_addr + max(1, _set.meta.used_count) * 64]);
    }

    // Size estimate for the code block: BITMAP ~160, SPRITE ~60, multiplexer per band
    var _multi = (array_length(_rows) > 1);
    var _mux_nodes = _multi && _o.mux_nodes;
    var _code = "";
    var _est = 200 + _n * 64;
    if (_multi) {
        if (_mux_nodes) {
            // A MACRO_SPR is ~64 bytes, a VWAIT ~25
            _est = 200 + _n * 64 + array_length(_rows) * 28;
        } else {
            _code = scr_bmp_spr_frame_code(_clean, _set, _rows, _o, _rg.scr_addr, _ptr0);
            // Comment lines assemble to nothing
            var _code_lines = string_count("\n", _code) - string_count(";", _code);
            _est = 200 + _code_lines * 3 + 32;
        }
    }
    var _org_addr = scr_bmp_spr_free_code(_est, _excl);
    if (_org_addr < 0) { scr_show_message("SETUP NODES\n\nThere is no free RAM for the code block (" + string(_est) + " bytes)."); return; }

    // The ORG, in its own column right of everything
    var _x = _init.x;
    with (obj_c64_node) { if (node_type == "ORG" || node_type == "INIT") _x = max(_x, x); }
    _x += global.node_display_width + 120;
    var _org = scr_spawn_org_node(_x, _init.y);
    _org.node_title   = _clean + " SETUP";
    _org.proxy        = false;
    _org.proxy_address = _org_addr;
    _org.pc_address   = _org_addr;
    _org.instructions = [["org", _org_addr]];
    var _y = _org.y + _org.height;

    var _lbl = scr_bmp_spr_node("LABEL", [["label", _clean + "_SHOW"]], _x, _y, _org);
    _lbl.instructions[0][1] = scr_make_unique_node_name(_clean + "_SHOW", _lbl);
    var _show = _lbl.instructions[0][1];
    _y += _lbl.height;
    var _nd = scr_bmp_spr_node("MACRO_SPR_ENABLE", [["macro_spr_enable", 255, 1]], _x, _y, _org); _y += _nd.height;
    _nd = scr_bmp_spr_node("MACRO_BMP", [["macro_bmp", _asset.name, _bmp_addr, 0, 0]], _x, _y, _org); _y += _nd.height;
    if (!_multi && _n > 0) {
        var _sp = _rows[0].sprites;
        for (var _k = 0; _k < min(array_length(_sp), 8); _k++) {
            _nd = scr_bmp_spr_node("MACRO_SPR", [["macro_spr", _set.name, _k, _sp[_k].x + 24, _sp[_k].y + 50, _k, (_k == 0) ? 1 : 0]], _x, _y, _org);
            _y += _nd.height;
        }
    }
    _nd = scr_bmp_spr_node("NORMAL", [["rts", 0]], _x, _y, _org); _nd.node_title = "RTS"; _y += _nd.height;

    var _frame = "";
    if (_multi) {
        _lbl = scr_bmp_spr_node("LABEL", [["label", _clean + "_FRAME"]], _x, _y, _org);
        _lbl.instructions[0][1] = scr_make_unique_node_name(_clean + "_FRAME", _lbl);
        _frame = _lbl.instructions[0][1];
        _y += _lbl.height;
        if (_mux_nodes) {
            // Band 0 at the top of the frame (puts the sprites back up after the
            // last band), then for each later band wait for the raster and move
            // the 8 hardware sprites down onto it.
            var _slot0 = 0;
            for (var _r = 0; _r < array_length(_rows); _r++) {
                var _bsp = _rows[_r].sprites;
                var _bn  = min(array_length(_bsp), 8);
                var _byy = _rows[_r].y + 50;
                if (_r > 0) {
                    // A MACRO_SPR takes ~2 raster lines, so start early enough to
                    // finish before the band - but not before the previous band
                    // has started, or its sprites would be moved off it.
                    var _prev_yy = _rows[_r - 1].y + 50;
                    var _wait = max(_prev_yy, _byy - 2 - _bn * 2);
                    _nd = scr_bmp_spr_node("MACRO_VWAIT", [["macro_vwait", _wait, 0, ""]], _x, _y, _org);
                    _y += _nd.height;
                }
                for (var _k = 0; _k < _bn; _k++) {
                    var _glob = 0;
                    if (_r == 0 && _k == 0) {
                        _glob = 1;
                    }
                    _nd = scr_bmp_spr_node("MACRO_SPR", [["macro_spr", _set.name, _k, _bsp[_k].x + 24, _bsp[_k].y + 50, _slot0 + _k, _glob]], _x, _y, _org);
                    _y += _nd.height;
                }
                _slot0 += array_length(_bsp);
            }
            _nd = scr_bmp_spr_node("NORMAL", [["rts", 0]], _x, _y, _org); _nd.node_title = "RTS";
        } else {
            _nd = scr_node_spawn("MACRO_CODE", _x, _y);
            _nd.code_descriptor    = _clean + " MULTIPLEXER";
            _nd.instructions[0][1] = _code;
            _nd.code_cache_dirty   = true;
            _nd.height_dirty       = true;
            _nd.is_connected       = true;
            _nd.org_parent         = _org;
            with (_nd) event_user(0);
            scr_macro_sync_height(_nd);
            _y += _nd.height;
            _nd = scr_bmp_spr_node("NORMAL", [["rts", 0]], _x, _y, _org); _nd.node_title = "RTS";
        }
    }
    _o.gen_org = _org.stable_uid;

    global.addresses_dirty   = true;
    global.memory_bar_dirty  = true;
    global.node_change_dirty = true;
    global.autosave_dirty    = true;
    scr_c64_do_update_addresses();
    obj_workspace_manager.flow_overlay_dirty = true;
    scr_undo_snapshot();
    global.undo_dirty = false;
    scr_focus_camera_on_node(_org);
    // Re-measure and re-pack the new nodes once the editor closes (obj_workspace_manager Step)
    obj_workspace_manager.setup_settle_org   = _org;
    obj_workspace_manager.setup_settle_timer = 4;

    var _msg = "SETUP NODES\n\nYour nodes are set up at " + scr_bmp_spr_hex(_org_addr, 4) + ". Just JSR " + _show + ".";
    if (_n > 0) _msg += "\n\n" + string(_n) + " sprite(s) are in " + _set.name + " at " + scr_bmp_spr_hex(_set.address, 4) + ".";
    if (_multi) {
        _msg += "\n\nMore than one row: also JSR " + _frame + " once every frame, before the first band"
              + " (e.g. right after a VWAIT at the bottom of the screen). Sprites are grouped into bands by Y;"
              + " leave a gap of a few lines between bands so there is time to move the sprites down.";
        if (_mux_nodes) {
            _msg += "\n\nMUX: NODES - each MACRO_SPR takes about 2 raster lines, so a full row of 8 needs ~16 lines"
                  + " to set up. Leave a gap between rows (or use MUX: CODE, which is much faster) or the"
                  + " bottom of the row above can jump.";
        }
    }
    scr_show_message(_msg);
}
