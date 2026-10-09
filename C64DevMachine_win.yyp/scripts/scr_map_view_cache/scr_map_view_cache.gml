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

/// Glyph atlas for one charset buffer into a buffer laid out as above.
/// Used for the extra ROOM VIEW charsets (no per-glyph change tracking:
/// a change to one of those charsets redraws the whole map).
function scr_map_cache_fill_atlas_buf(_ab, _buf) {
    var _bsize = buffer_get_size(_buf);
    buffer_fill(_ab, 0, buffer_u32, 0, buffer_get_size(_ab));
    for (var _ch = 0; _ch < 256; _ch++) {
        var _ax = (_ch mod 16) * 8;
        var _ay = (_ch div 16) * 8;
        for (var _r = 0; _r < 8; _r++) {
            var _off = _ch * 8 + _r;
            if (_off >= _bsize) continue;
            var _byte = buffer_peek(_buf, _off, buffer_u8);
            if (_byte == 0) continue;
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
}

/// ROOM VIEW: charset slot and colours for the cell at col,row.
/// Returns [atlas, bg, col1, col2] - the map's own when the cell has no room view.
function scr_map_cache_cell_look(_c, _col, _row) {
    var _look = [_c.atlas, _c.bg_c, _c.col1_c, _c.col2_c];
    if (!_c.rv_on) return _look;
    var _rx_i = _col div _c.rv_rw;
    if (_rx_i >= _c.rv_rx) return _look;
    var _ri = (_row div _c.rv_rh) * _c.rv_rx + _rx_i;
    if (_ri >= _c.rv_n) return _look;
    var _sl = _c.rv_slot[_ri];
    if (_sl > 0) {
        if (surface_exists(_c.rv_atlas[_sl])) _look[0] = _c.rv_atlas[_sl];
    }
    var _bi = _ri * _c.rv_rh + (_row mod _c.rv_rh);
    _look[1] = _c.rv_bg[_bi];
    _look[2] = _c.rv_c1[_bi];
    _look[3] = _c.rv_c2[_bi];
    return _look;
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
    var _look = scr_map_cache_cell_look(_c, _col, _row);
    var _at   = _look[0];

    if (_c.mixed == 1 && _ov == 1) {
        draw_surface_part_ext(_at, 0, 512, 8, 8, _x, _y, 1, 1, _look[1], 1);
        if (_char >= 0 && _char < 256) {
            var _ax = (_char mod 16) * 8;
            var _ay = (_char div 16) * 8;
            draw_surface_part_ext(_at, _ax, _ay + 128, 8, 8, _x, _y, 1, 1, _look[2], 1);
            draw_surface_part_ext(_at, _ax, _ay + 256, 8, 8, _x, _y, 1, 1, _look[3], 1);
            draw_surface_part_ext(_at, _ax, _ay + 384, 8, 8, _x, _y, 1, 1, _c.pal[_col_v & 0x07], 1);
        }
        return;
    }

    var _real = _char;
    var _bgc  = _look[1];
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

    // ROOM VIEW: meta.room_view[room] = { chr: charset name ("" = the map's),
    //   bands: [[first row, bg, mc1, mc2], ...] }. Rows of a room take the
    //   last band whose first row is at or above them; no band = the map's.
    var _rv    = _m[$ "room_view"];
    var _rv_on = false;
    if (is_array(_rv) && array_length(_rv) > 0 && real(_m.raw_chars) >= 2
        && real(_m.room_w) > 0 && real(_m.room_h) > 0) {
        _rv_on = true;
    }
    var _rv_key = "";
    if (_rv_on) {
        _rv_key = json_stringify(_rv);
    }
    if (_c.rv_on != _rv_on || _c.rv_key != _rv_key) _full = true;
    _c.rv_on  = _rv_on;
    _c.rv_key = _rv_key;
    if (_rv_on) {
        _c.rv_rw = real(_m.room_w);
        _c.rv_rh = real(_m.room_h);
        _c.rv_rx = max(1, _gw div _c.rv_rw);
        _c.rv_n  = array_length(_rv);
        _c.rv_slot = array_create(_c.rv_n, 0);
        _c.rv_bg   = array_create(_c.rv_n * _c.rv_rh, _c.bg_c);
        _c.rv_c1   = array_create(_c.rv_n * _c.rv_rh, _c.col1_c);
        _c.rv_c2   = array_create(_c.rv_n * _c.rv_rh, _c.col2_c);
        _c.rv_chr[0] = _chr;
        for (var _ri = 0; _ri < _c.rv_n; _ri++) {
            var _ent = _rv[_ri];
            if (!is_struct(_ent)) continue;
            // charset slot
            var _cn = _ent[$ "chr"];
            if (is_string(_cn) && _cn != "" && _cn != _chr.name) {
                var _sl = -1;
                for (var _k = 1; _k < array_length(_c.rv_chr); _k++) {
                    if (_c.rv_chr[_k] != noone && _c.rv_chr[_k].name == _cn) { _sl = _k; break; }
                }
                if (_sl == -1) {
                    var _ca = noone;
                    var _al = obj_asset_manager.asset_list;
                    for (var _ai = 0; _ai < ds_list_size(_al); _ai++) {
                        var _aa = ds_list_find_value(_al, _ai);
                        if (_aa.type == "CHAR_SET" && _aa.name == _cn) { _ca = _aa; break; }
                    }
                    if (_ca != noone && buffer_exists(_ca.buffer)) {
                        array_push(_c.rv_chr, _ca);
                        array_push(_c.rv_atlas, -1);
                        array_push(_c.rv_crc, -1);
                        _sl = array_length(_c.rv_chr) - 1;
                    }
                }
                if (_sl > 0) _c.rv_slot[_ri] = _sl;
            }
            // colour bands
            var _bands = _ent[$ "bands"];
            if (is_array(_bands)) {
                for (var _rr = 0; _rr < _c.rv_rh; _rr++) {
                    for (var _bi = 0; _bi < array_length(_bands); _bi++) {
                        var _bd = _bands[_bi];
                        if (real(_bd[0]) <= _rr) {
                            var _o = _ri * _c.rv_rh + _rr;
                            _c.rv_bg[_o] = scr_c64_pepto_colour(real(_bd[1]) & 0x0F);
                            _c.rv_c1[_o] = scr_c64_pepto_colour(real(_bd[2]) & 0x0F);
                            _c.rv_c2[_o] = scr_c64_pepto_colour(real(_bd[3]) & 0x0F);
                        }
                    }
                }
            }
        }
        // extra charsets: (re)build their atlases when they change
        for (var _k = 1; _k < array_length(_c.rv_chr); _k++) {
            var _kc = _c.rv_chr[_k];
            if (_kc == noone || !buffer_exists(_kc.buffer)) continue;
            var _kcrc = buffer_crc32(_kc.buffer, 0, buffer_get_size(_kc.buffer));
            if (!surface_exists(_c.rv_atlas[_k]) || _c.rv_crc[_k] != _kcrc) {
                if (!surface_exists(_c.rv_atlas[_k])) _c.rv_atlas[_k] = surface_create(128, 520);
                var _tmp = buffer_create(128 * 520 * 4, buffer_fixed, 1);
                scr_map_cache_fill_atlas_buf(_tmp, _kc.buffer);
                buffer_set_surface(_tmp, _c.rv_atlas[_k], 0);
                buffer_delete(_tmp);
                _c.rv_crc[_k] = _kcrc;
                _full = true;
            }
        }
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


/// Small text button for the ROOM PREVIEW panel (text centred in the box).
/// Returns 1 on a left click, 2 on a right click, 0 otherwise.
function scr_mrp_button(_x1, _y1, _x2, _y2, _label, _on, _mx, _my) {
    var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2);
    var _col = make_color_rgb(30, 30, 45);
    if (_on) { _col = make_color_rgb(40, 110, 60); }
    else if (_hov) { _col = make_color_rgb(55, 55, 80); }
    draw_set_color(_col);
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text((_x1 + _x2) * 0.5, (_y1 + _y2) * 0.5 - scr_lang_lift(), _label);
    draw_set_valign(fa_top);
    draw_set_halign(fa_left);
    if (_hov && mouse_check_button_pressed(mb_left)) return 1;
    if (_hov && mouse_check_button_pressed(mb_right)) return 2;
    return 0;
}

/// ROOM PREVIEW (map editor top panel, room maps): one room the way the
/// game shows it - its own charset and colour bands (meta.room_view) and,
/// with Y x2 on, every cell twice as tall (Bruce Lee doubles each tile row).
/// Scaled to fill the panel height, centred, with its controls in a column
/// beside it:
///   < ROOM >        previous / next room      FOLLOW  track the mouse room
///   Y x2 / TAGS     row doubling / tag badges
///   CHR             L-click next charset, R-click back to the map's own
///   band ROW        L +1 / R -1                swatches L next / R previous colour
///   X               delete the band            + BAND  add one under the last
function scr_map_room_preview_panel(_asset, _x1, _y1, _x2, _y2, _mx, _my) {
    var _m   = _asset.meta;
    var _rw  = real(_m.room_w);
    var _rh  = real(_m.room_h);
    var _gw  = real(_m.grid_w);
    var _rx  = max(1, _gw div _rw);
    var _rn  = _rx * max(1, real(_m.grid_h) div _rh);
    if (real(_m.room_count) > 0 && real(_m.room_count) < _rn) _rn = real(_m.room_count);
    if (_y2 - _y1 < 40) return;
    if (map_prev_follow && map_hover_room >= 0 && map_hover_room < _rn) map_prev_room = map_hover_room;
    map_prev_room = clamp(map_prev_room, 0, max(0, _rn - 1));
    var _r = map_prev_room;

    // ---- layout: preview scaled to the height, controls beside it ----
    var _ysc  = 1;
    if (_m.view_y2) _ysc = 2;
    var _pw   = _rw * 8;
    var _ph   = _rh * 8 * _ysc;
    var _colw = 214;
    var _sc   = min((_y2 - _y1 - 4) / _ph, (_x2 - _x1 - _colw - 16) / _pw);
    _sc = max(0.25, _sc);
    var _vw = _pw * _sc;
    var _vh = _ph * _sc;
    var _gx = _x1 + max(0, ((_x2 - _x1) - (_vw + 12 + _colw)) * 0.5);
    var _px = _gx + 2;
    var _py = _y1 + 2;

    draw_set_color(make_color_rgb(12, 12, 20));
    draw_rectangle(_gx - 4, _y1 - 2, _gx + _vw + 12 + _colw + 4, _y2, false);
    var _c = map_view_cache;
    if (_c.asset == _asset && surface_exists(_c.surf)) {
        var _tf = gpu_get_tex_filter();
        gpu_set_tex_filter(false);
        draw_surface_part_ext(_c.surf, (_r mod _rx) * _pw, (_r div _rx) * _rh * 8, _pw, _rh * 8,
            _px, _py, _sc, _sc * _ysc, c_white, 1);
        gpu_set_tex_filter(_tf);
    }
    draw_set_color(c_yellow);
    draw_rectangle(_px - 1, _py - 1, _px + _vw, _py + _vh, true);

    // ---- controls column ----
    var _cx = _px + _vw + 10;
    var _cy = _y1 + 2;
    var _bh = 18;
    var _st = _bh + 4;
    scr_ui_info(point_in_rectangle(_mx, _my, _cx, _cy, _cx + 24, _cy + _bh), "PREVIEW THE PREVIOUS ROOM (TURNS FOLLOW OFF)");
    scr_ui_info(point_in_rectangle(_mx, _my, _cx + 120, _cy, _cx + 144, _cy + _bh), "PREVIEW THE NEXT ROOM (TURNS FOLLOW OFF)");
    scr_ui_info(point_in_rectangle(_mx, _my, _cx + 150, _cy, _cx + _colw, _cy + _bh), "FOLLOW: THE PREVIEW SHOWS WHICHEVER ROOM THE MOUSE IS OVER ON THE MAP");
    scr_ui_info(point_in_rectangle(_mx, _my, _cx, _cy + _st, _cx + 104, _cy + _st + _bh), "DOUBLE EVERY ROW IN THE PREVIEW, LIKE BRUCE LEE'S ROOMS (H)");
    scr_ui_info(point_in_rectangle(_mx, _my, _cx + 110, _cy + _st, _cx + _colw, _cy + _st + _bh), "SHOW / HIDE EACH CELL'S TILE TYPE TAG ON THE MAP (T)");
    scr_ui_info(point_in_rectangle(_mx, _my, _cx, _cy + _st * 2, _cx + _colw, _cy + _st * 2 + _bh), "THIS ROOM'S CHARSET - LMB NEXT CHAR_SET, RMB BACK TO THE MAP'S OWN CHARSET");
    if (scr_mrp_button(_cx, _cy, _cx + 24, _cy + _bh, "<", false, _mx, _my) == 1) {
        map_prev_follow = false;
        map_prev_room = (map_prev_room + _rn - 1) mod _rn;
    }
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text(_cx + 72, _cy + _bh * 0.5 - scr_lang_lift(), "ROOM " + string(_r));
    draw_set_valign(fa_top);
    draw_set_halign(fa_left);
    if (scr_mrp_button(_cx + 120, _cy, _cx + 144, _cy + _bh, ">", false, _mx, _my) == 1) {
        map_prev_follow = false;
        map_prev_room = (map_prev_room + 1) mod _rn;
    }
    if (scr_mrp_button(_cx + 150, _cy, _cx + _colw, _cy + _bh, "FOLLOW", map_prev_follow, _mx, _my) == 1) {
        map_prev_follow = !map_prev_follow;
    }
    _cy += _st;
    if (scr_mrp_button(_cx, _cy, _cx + 104, _cy + _bh, "Y x2", _m.view_y2, _mx, _my) == 1) {
        _m.view_y2 = !_m.view_y2;
        _m.is_dirty = true;
    }
    if (scr_mrp_button(_cx + 110, _cy, _cx + _colw, _cy + _bh, "TAGS", map_show_tags, _mx, _my) == 1) {
        map_show_tags = !map_show_tags;
    }
    _cy += _st;

    // the room's view entry (created on the first edit)
    if (!is_array(_m.room_view)) _m.room_view = [];
    var _ent = { chr: "", bands: [] };
    if (_r < array_length(_m.room_view) && is_struct(_m.room_view[_r])) _ent = _m.room_view[_r];
    if (!is_string(_ent[$ "chr"])) _ent.chr = "";
    var _edited = false;

    // charset
    var _chr_lbl = "CHR: MAP";
    if (_ent.chr != "") _chr_lbl = "CHR: " + _ent.chr;
    var _cb = scr_mrp_button(_cx, _cy, _cx + _colw, _cy + _bh, _chr_lbl, false, _mx, _my);
    if (_cb != 0) {
        var _names = [];
        for (var _ai = 0; _ai < ds_list_size(asset_list); _ai++) {
            var _aa = ds_list_find_value(asset_list, _ai);
            if (_aa.type == "CHAR_SET") array_push(_names, _aa.name);
        }
        if (_cb == 2 || array_length(_names) == 0) {
            _ent.chr = "";
        } else {
            var _at = -1;
            for (var _ni = 0; _ni < array_length(_names); _ni++) {
                if (_names[_ni] == _ent.chr) { _at = _ni; break; }
            }
            _ent.chr = _names[(_at + 1) mod array_length(_names)];
        }
        _edited = true;
    }
    _cy += _st;

    // colour bands
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_set_valign(fa_middle);
    draw_text(_cx,       _cy + 7 - scr_lang_lift(), "ROW");
    draw_text(_cx + 44,  _cy + 7 - scr_lang_lift(), "BG");
    draw_text(_cx + 82,  _cy + 7 - scr_lang_lift(), "MC1");
    draw_text(_cx + 120, _cy + 7 - scr_lang_lift(), "MC2");
    draw_set_valign(fa_top);
    _cy += 16;
    if (!is_array(_ent[$ "bands"])) _ent.bands = [];
    var _bands = _ent.bands;
    var _del = -1;
    for (var _bi = 0; _bi < array_length(_bands); _bi++) {
        var _bd = _bands[_bi];
        if (_cy + _bh > _y2 - _st) break;    // keep a row for + BAND
        scr_ui_info(point_in_rectangle(_mx, _my, _cx, _cy, _cx + 32, _cy + _bh), "ROW THIS COLOUR BAND STARTS ON - LMB +1, RMB -1");
        scr_ui_info(point_in_rectangle(_mx, _my, _cx + _colw - 24, _cy, _cx + _colw, _cy + _bh), "DELETE THIS COLOUR BAND");
        var _rb = scr_mrp_button(_cx, _cy, _cx + 32, _cy + _bh, string(real(_bd[0])), false, _mx, _my);
        if (_rb == 1) { _bd[@ 0] = min(_rh - 1, real(_bd[0]) + 1); _edited = true; }
        if (_rb == 2) { _bd[@ 0] = max(0, real(_bd[0]) - 1); _edited = true; }
        for (var _k = 1; _k <= 3; _k++) {
            var _sx1 = _cx + 44 + (_k - 1) * 38;
            var _shov = point_in_rectangle(_mx, _my, _sx1, _cy, _sx1 + 30, _cy + _bh);
            scr_ui_info(_shov, "BAND " + ((_k == 1) ? "BACKGROUND" : ((_k == 2) ? "MC1" : "MC2")) + " COLOUR FROM THIS ROW DOWN - LMB NEXT COLOUR, RMB PREVIOUS");
            draw_set_color(scr_c64_pepto_colour(real(_bd[_k]) & 0x0F));
            draw_rectangle(_sx1, _cy, _sx1 + 30, _cy + _bh, false);
            if (_shov) { draw_set_color(c_white); } else { draw_set_color(c_black); }
            draw_rectangle(_sx1, _cy, _sx1 + 30, _cy + _bh, true);
            if (_shov && mouse_check_button_pressed(mb_left))  { _bd[@ _k] = (real(_bd[_k]) + 1) & 0x0F; _edited = true; }
            if (_shov && mouse_check_button_pressed(mb_right)) { _bd[@ _k] = (real(_bd[_k]) + 15) & 0x0F; _edited = true; }
        }
        if (scr_mrp_button(_cx + _colw - 24, _cy, _cx + _colw, _cy + _bh, "X", false, _mx, _my) == 1) _del = _bi;
        _cy += _st;
    }
    if (_del >= 0) {
        array_delete(_bands, _del, 1);
        _edited = true;
    }
    if (_cy + _bh <= _y2) {
        scr_ui_info(point_in_rectangle(_mx, _my, _cx, _cy, _cx + 104, _cy + _bh), "ADD A COLOUR BAND ONE ROW BELOW THE LAST (COPIES ITS COLOURS)");
        if (scr_mrp_button(_cx, _cy, _cx + 104, _cy + _bh, "+ BAND", false, _mx, _my) == 1) {
            var _nb = [0, 0, 1, 2];
            if (array_length(_bands) > 0) {
                var _lb = _bands[array_length(_bands) - 1];
                _nb = [min(_rh - 1, real(_lb[0]) + 1), real(_lb[1]), real(_lb[2]), real(_lb[3])];
            }
            array_push(_bands, _nb);
            _edited = true;
        }
    }

    if (_edited) {
        while (array_length(_m.room_view) <= _r) array_push(_m.room_view, { chr: "", bands: [] });
        _m.room_view[_r] = _ent;
        _m.is_dirty = true;
    }
}
