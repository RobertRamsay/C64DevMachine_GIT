/// META_TILESET glyph atlas.
///
/// The tileset editor used to draw every char pixel with its own
/// draw_rectangle, every frame, in four places (stamp list, edit canvas,
/// map view, char strip). Instead each of the 256 chars is rendered once into
/// four white mask layers of one 512x128 surface:
///
///   x   0..127  HR  - bit set
///   x 128..255  MC  - pair %01  ($D022)
///   x 256..383  MC  - pair %10  ($D023)
///   x 384..511  MC  - pair %11  (colour RAM)
///
/// Char c sits at ((c mod 16) * 8, (c div 16) * 8) inside each layer. Drawing a
/// cell is then a background rect plus one tinted blit (HR) or three (MC).
///
/// The masks are built in a CPU-side RGBA buffer and uploaded with
/// buffer_set_surface, so surface loss is a re-upload, not a re-render.
/// Change detection is a crc32 of the charset; when it moves, only the chars
/// whose 8 bytes differ from a shadow copy are re-rendered. While a mouse
/// button is held that happens at most every 100ms; on release, at once.
///
/// State lives on obj_asset_manager (initialised in its Create event).

/// @param {struct} _chr  Linked CHAR_SET asset, or noone
function scr_mts_atlas_update(_chr) {
    with (obj_asset_manager) {
        mts_atlas_ok = false;
        if (_chr == noone) { exit; }
        if (!buffer_exists(_chr.buffer)) { exit; }

        var _src    = _chr.buffer;
        var _src_sz = min(buffer_get_size(_src), 2048);

        var _full = false;
        if (mts_atlas_owner != _chr.name) { _full = true; }
        if (mts_atlas_src_sz != _src_sz)  { _full = true; }

        var _dirty = false;
        if (_full) {
            for (var _c = 0; _c < 256; _c++) {
                scr_mts_atlas_write_glyph(mts_atlas_pix, _src, _src_sz, _c);
            }
            buffer_fill(mts_atlas_shadow, 0, buffer_u8, 0, 2048);
            buffer_copy(_src, 0, _src_sz, mts_atlas_shadow, 0);
            mts_atlas_owner  = _chr.name;
            mts_atlas_src_sz = _src_sz;
            _dirty = true;
        } else {
            var _crc = buffer_crc32(_src, 0, _src_sz);
            if (_crc != mts_atlas_crc) {
                var _held = mouse_check_button(mb_left) || mouse_check_button(mb_right);
                var _go   = true;
                if (_held && current_time < mts_atlas_next_ms) { _go = false; }
                if (_go) {
                    for (var _c2 = 0; _c2 < 256; _c2++) {
                        var _base = _c2 * 8;
                        if (_base >= _src_sz) { break; }
                        var _diff = false;
                        for (var _r = 0; _r < 8; _r++) {
                            var _o = _base + _r;
                            if (_o >= _src_sz) { break; }
                            if (buffer_peek(_src, _o, buffer_u8) != buffer_peek(mts_atlas_shadow, _o, buffer_u8)) {
                                _diff = true;
                                break;
                            }
                        }
                        if (_diff) {
                            scr_mts_atlas_write_glyph(mts_atlas_pix, _src, _src_sz, _c2);
                            var _len = min(8, _src_sz - _base);
                            buffer_copy(_src, _base, _len, mts_atlas_shadow, _base);
                        }
                    }
                    _dirty = true;
                }
            }
        }

        if (_dirty) {
            mts_atlas_crc     = buffer_crc32(_src, 0, _src_sz);
            mts_atlas_next_ms = current_time + 100;
            mts_atlas_upload  = true;
        }

        if (!surface_exists(mts_atlas_surf)) {
            mts_atlas_surf   = surface_create(512, 128);
            mts_atlas_upload = true;
        }
        if (mts_atlas_upload) {
            buffer_set_surface(mts_atlas_pix, mts_atlas_surf, 0);
            mts_atlas_upload = false;
        }
        mts_atlas_ok = true;
    }
}

/// Render one char's four mask layers into the RGBA pixel buffer.
/// @param {Id.Buffer} _pix     512x128 RGBA atlas buffer
/// @param {Id.Buffer} _src     Charset buffer
/// @param {real}      _src_sz  Usable bytes in _src (chars past it render blank)
/// @param {real}      _c       Char index 0-255
function scr_mts_atlas_write_glyph(_pix, _src, _src_sz, _c) {
    var _gx = (_c mod 16) * 8;
    var _gy = (_c div 16) * 8;
    for (var _r = 0; _r < 8; _r++) {
        var _o = (_c * 8) + _r;
        var _b = 0;
        if (_o < _src_sz) { _b = buffer_peek(_src, _o, buffer_u8); }
        var _row = ((_gy + _r) * 512 + _gx) * 4;
        for (var _p = 0; _p < 8; _p++) {
            var _hr = 0;
            if ((_b & (0x80 >> _p)) != 0) { _hr = 0xFFFFFFFF; }
            var _pair = (_b >> (6 - (_p div 2) * 2)) & 0x03;
            var _m1 = 0;
            var _m2 = 0;
            var _m3 = 0;
            if (_pair == 1) { _m1 = 0xFFFFFFFF; }
            if (_pair == 2) { _m2 = 0xFFFFFFFF; }
            if (_pair == 3) { _m3 = 0xFFFFFFFF; }
            buffer_poke(_pix, _row + (_p * 4),               buffer_u32, _hr);
            buffer_poke(_pix, _row + ((128 + _p) * 4),       buffer_u32, _m1);
            buffer_poke(_pix, _row + ((256 + _p) * 4),       buffer_u32, _m2);
            buffer_poke(_pix, _row + ((384 + _p) * 4),       buffer_u32, _m3);
        }
    }
}

/// Draw one char cell from the atlas: background, then the tinted layer(s).
/// Colours are GameMaker colours (already through scr_c64_pepto_colour).
/// @param {real} _rc      Real char index 0-255 (ECM: already mod 64)
/// @param {real} _x
/// @param {real} _y
/// @param {real} _w       Cell width in pixels
/// @param {real} _h       Cell height in pixels
/// @param {bool} _is_mc   Multicolour cell
/// @param {real} _bg      Background ($D021 / ECM band)
/// @param {real} _fg      HR ink, or MC %11 (colour RAM)
/// @param {real} _mc1     MC %01 ($D022)
/// @param {real} _mc2     MC %10 ($D023)
function scr_mts_draw_glyph(_rc, _x, _y, _w, _h, _is_mc, _bg, _fg, _mc1, _mc2) {
    draw_set_color(_bg);
    draw_rectangle(_x, _y, _x + _w - 1, _y + _h - 1, false);

    var _surf = obj_asset_manager.mts_atlas_surf;
    if (!surface_exists(_surf)) { exit; }

    var _c  = clamp(floor(_rc), 0, 255);
    var _gx = (_c mod 16) * 8;
    var _gy = (_c div 16) * 8;
    var _sx = _w / 8;
    var _sy = _h / 8;

    // Project has pixel interpolation on - scaled glyphs must stay sharp
    // and must not bleed in from their atlas neighbours.
    var _tf_prev = gpu_get_texfilter();
    gpu_set_texfilter(false);
    if (_is_mc) {
        draw_surface_part_ext(_surf, 128 + _gx, _gy, 8, 8, _x, _y, _sx, _sy, _mc1, 1);
        draw_surface_part_ext(_surf, 256 + _gx, _gy, 8, 8, _x, _y, _sx, _sy, _mc2, 1);
        draw_surface_part_ext(_surf, 384 + _gx, _gy, 8, 8, _x, _y, _sx, _sy, _fg,  1);
    } else {
        draw_surface_part_ext(_surf, _gx, _gy, 8, 8, _x, _y, _sx, _sy, _fg, 1);
    }
    gpu_set_texfilter(_tf_prev);
}
