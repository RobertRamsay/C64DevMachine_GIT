/// MAP_DATA view cache.
/// The whole map is rendered once at 1:1 (8px per cell) into a surface and
/// blitted at the current zoom. Cells are only re-rendered when their char,
/// colour or MC override changes, or when the charset glyph they use changes.
/// Glyphs come from a mask atlas (white on transparent) tinted per draw, so a
/// cell costs 2-4 blits instead of up to 64 rectangles.
///
/// Atlas layout (128 x 520): four 128x128 sections, 16x16 chars of 8x8 each
///   y   0 : hires mask (1 bit per pixel)
///   y 128 : MC bit-pair %01
///   y 256 : MC bit-pair %10
///   y 384 : MC bit-pair %11
///   y 512 : solid 8x8 white block (cell background)

function scr_map_cache_build_atlas(_c, _buf) {
    var _changed = array_create(256, false);
    var _bsize   = buffer_get_size(_buf);
    var _ab      = _c.atlas_buf;
    buffer_fill(_ab, 0, buffer_u32, 0, buffer_get_size(_ab));

    for (var _ch = 0; _ch < 256; _ch++) {
        var _ax = (_ch mod 16) * 8;
        var _ay = (_ch div 16) * 8;
        for (var _r = 0; _r < 8; _r++) {
            var _off  = _ch * 8 + _r;
            var _byte = -1;
            if (_off < _bsize) {
                _byte = buffer_peek(_buf, _off, buffer_u8);
            }
            if (_c.glyph_bytes[_off] != _byte) {
                _changed[_ch] = true;
                _c.glyph_bytes[_off] = _byte;
            }
            if (_byte <= 0) continue;
            var _py = _ay + _r;
            for (var _b = 0; _b < 8; _b++) {
                if (_byte & (0x80 >> _b)) {
                    buffer_poke(_ab, ((_py * 128) + _ax + _b) * 4, buffer_u32, 0xFFFFFFFF);
                }
            }
            for (var _p = 0; _p < 4; _p++) {
                var _bits = (_byte >> (6 - _p * 2)) & 0x03;
                if (_bits == 0) continue;
                var _sy = _py + _bits * 128;
                var _sx = _ax + _p * 2;
                buffer_poke(_ab, ((_sy * 128) + _sx) * 4,     buffer_u32, 0xFFFFFFFF);
                buffer_poke(_ab, ((_sy * 128) + _sx + 1) * 4, buffer_u32, 0xFFFFFFFF);
            }
        }
    }
    for (var _sy2 = 512; _sy2 < 520; _sy2++) {
        for (var _sx2 = 0; _sx2 < 8; _sx2++) {
            buffer_poke(_ab, ((_sy2 * 128) + _sx2) * 4, buffer_u32, 0xFFFFFFFF);
        }
    }
    buffer_set_surface(_ab, _c.atlas, 0);
    return _changed;
}

function scr_map_cache_draw_cell(_c, _m, _col, _row) {
    var _idx   = _row * _c.gw + _col;
    var _char  = _m.char_grid[_idx];
    var _col_v = _m.colour_grid[_idx];
    var _ov    = 0;
    if (_c.ov_len > _idx) {
        _ov = _m.override_grid[_idx];
    }
    var _x = _col * 8;
    var _y = _row * 8;
    var _at = _c.atlas;

    if (_c.mixed == 1 && _ov == 1) {
        draw_surface_part_ext(_at, 0, 512, 8, 8, _x, _y, 1, 1, _c.bg_c, 1);
        if (_char >= 0 && _char < 256) {
            var _ax = (_char mod 16) * 8;
            var _ay = (_char div 16) * 8;
            draw_surface_part_ext(_at, _ax, _ay + 128, 8, 8, _x, _y, 1, 1, _c.col1_c, 1);
            draw_surface_part_ext(_at, _ax, _ay + 256, 8, 8, _x, _y, 1, 1, _c.col2_c, 1);
            draw_surface_part_ext(_at, _ax, _ay + 384, 8, 8, _x, _y, 1, 1, _c.pal[_col_v & 0x07], 1);
        }
        return;
    }

    var _real = _char;
    var _bgc  = _c.bg_c;
    if (_c.ecm) {
        _real = _char mod 64;
        _bgc  = _c.ecm_c[clamp(_char div 64, 0, 3)];
    }
    var _rc = _col_v & 0x0F;
    if (_c.mixed != 0) {
        _rc = _col_v & 0x07;
    }
    draw_surface_part_ext(_at, 0, 512, 8, 8, _x, _y, 1, 1, _bgc, 1);
    if (_real >= 0 && _real < 256) {
        draw_surface_part_ext(_at, (_real mod 16) * 8, (_real div 16) * 8, 8, 8, _x, _y, 1, 1, _c.pal[_rc], 1);
    }
}

/// Compare a rectangle of cells against the shadow copies; re-render changes.
function scr_map_cache_scan(_c, _m, _c0, _r0, _c1, _r1) {
    var _gw = _c.gw;
    for (var _row = _r0; _row < _r1; _row++) {
        for (var _col = _c0; _col < _c1; _col++) {
            var _idx = _row * _gw + _col;
            var _ch  = _m.char_grid[_idx];
            var _cv  = _m.colour_grid[_idx];
            var _ov  = 0;
            if (_c.ov_len > _idx) {
                _ov = _m.override_grid[_idx];
            }
            if (_ch != _c.sh_chr[_idx] || _cv != _c.sh_col[_idx] || _ov != _c.sh_ov[_idx]) {
                _c.sh_chr[_idx] = _ch;
                _c.sh_col[_idx] = _cv;
                _c.sh_ov[_idx]  = _ov;
                scr_map_cache_draw_cell(_c, _m, _col, _row);
            }
        }
    }
}

/// Bring the cache up to date. _p = { gw, gh, bg, mixed, ecm, ecm_cols[4], col1, col2,
/// vc0, vr0, vc1, vr1 } (visible cell range). Returns true when the cache is drawable.
function scr_map_cache_update(_c, _asset, _chr, _p) {
    var _m  = _asset.meta;
    var _gw = _p.gw;
    var _gh = _p.gh;
    if (_gw <= 0 || _gh <= 0) return false;
    if (array_length(_m.char_grid) < _gw * _gh) return false;
    if (array_length(_m.colour_grid) < _gw * _gh) return false;

    var _key = string(_gw) + "x" + string(_gh) + "|" + string(_p.bg) + "|" + string(_p.mixed)
             + "|" + string(_p.ecm) + "|" + string(_p.ecm_cols[1]) + "," + string(_p.ecm_cols[2])
             + "," + string(_p.ecm_cols[3]) + "|" + string(_p.col1) + "," + string(_p.col2);

    var _full = false;
    if (_c.asset != _asset || _c.chr != _chr || _c.key != _key) _full = true;
    if ((current_time - _c.last_time) > 250) _full = true;   // was not on screen: resync everything
    _c.last_time = current_time;

    // per-frame render params
    _c.gw    = _gw;
    _c.gh    = _gh;
    _c.mixed = _p.mixed;
    _c.ecm   = _p.ecm;
    _c.bg_c  = scr_c64_pepto_colour(_p.bg);
    for (var _e = 0; _e < 4; _e++) {
        _c.ecm_c[_e] = scr_c64_pepto_colour(_p.ecm_cols[_e]);
    }
    var _pal_sum = 0;
    for (var _pc = 0; _pc < 16; _pc++) {
        _c.pal[_pc] = scr_c64_pepto_colour(_pc);
        _pal_sum += _c.pal[_pc] * (_pc + 1);
    }
    if (_c.pal_sum != _pal_sum) _full = true;   // palette switched
    _c.pal_sum = _pal_sum;
    _c.col1_c = scr_c64_pepto_colour(_p.col1);
    _c.col2_c = scr_c64_pepto_colour(_p.col2);
    _c.ov_len = 0;
    var _ovg = _m[$ "override_grid"];
    if (is_array(_ovg)) {
        _c.ov_len = array_length(_ovg);
    }

    // surfaces
    if (!surface_exists(_c.atlas)) {
        _c.atlas = surface_create(128, 520);
        _c.crc   = -1;
        _full    = true;
    }
    var _sw = _gw * 8;
    var _sh = _gh * 8;
    if (surface_exists(_c.surf)) {
        if (surface_get_width(_c.surf) != _sw || surface_get_height(_c.surf) != _sh) {
            surface_free(_c.surf);
        }
    }
    if (!surface_exists(_c.surf)) {
        _c.surf = surface_create(_sw, _sh);
        _full   = true;
    }

    var _old_tf = gpu_get_tex_filter();
    gpu_set_tex_filter(false);

    // charset glyphs
    var _crc = buffer_crc32(_chr.buffer, 0, buffer_get_size(_chr.buffer));
    if (_c.crc != _crc || _c.chr != _chr) {
        if (_c.chr != _chr) {
            _c.glyph_bytes = array_create(2048, -2);
        }
        var _changed = scr_map_cache_build_atlas(_c, _chr.buffer);
        _c.crc = _crc;
        if (!_full) {
            surface_set_target(_c.surf);
            for (var _i = 0; _i < _gw * _gh; _i++) {
                var _gc = _m.char_grid[_i];
                if (_gc < 0 || _gc > 255) continue;
                var _hit = _changed[_gc];
                if (_c.ecm) {
                    _hit = _hit || _changed[_gc mod 64];
                }
                if (_hit) {
                    scr_map_cache_draw_cell(_c, _m, _i mod _gw, _i div _gw);
                }
            }
            surface_reset_target();
        }
    }

    _c.asset = _asset;
    _c.chr   = _chr;
    _c.key   = _key;

    surface_set_target(_c.surf);
    if (_full) {
        var _n = _gw * _gh;
        _c.sh_chr = array_create(_n, 0);
        _c.sh_col = array_create(_n, 0);
        _c.sh_ov  = array_create(_n, 0);
        array_copy(_c.sh_chr, 0, _m.char_grid, 0, _n);
        array_copy(_c.sh_col, 0, _m.colour_grid, 0, _n);
        for (var _r = 0; _r < _gh; _r++) {
            for (var _cc = 0; _cc < _gw; _cc++) {
                var _fi = _r * _gw + _cc;
                if (_c.ov_len > _fi) {
                    _c.sh_ov[_fi] = _m.override_grid[_fi];
                }
                scr_map_cache_draw_cell(_c, _m, _cc, _r);
            }
        }
        _c.scan_row = 0;
    } else {
        var _released = mouse_check_button_released(mb_any) || keyboard_check_released(vk_anykey);
        var _held     = mouse_check_button(mb_any) || keyboard_check(vk_anykey);
        if (_released) {
            // stroke / fill / undo just finished: verify the whole map once
            scr_map_cache_scan(_c, _m, 0, 0, _gw, _gh);
        } else {
            if (_held) {
                scr_map_cache_scan(_c, _m, _p.vc0, _p.vr0, _p.vc1, _p.vr1);
            }
            // background sweep catches any off-screen change within a few frames
            var _rows = max(1, 4096 div _gw);
            var _r0   = _c.scan_row;
            if (_r0 >= _gh) _r0 = 0;
            var _r1   = min(_gh, _r0 + _rows);
            scr_map_cache_scan(_c, _m, 0, _r0, _gw, _r1);
            _c.scan_row = _r1;
        }
    }
    surface_reset_target();

    gpu_set_tex_filter(_old_tf);
    return true;
}
