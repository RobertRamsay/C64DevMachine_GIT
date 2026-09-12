/// @desc PNG STRIP -> SPRITE_SET import.
///
/// A PNG whose width is a multiple of 24 (hires pixels) or 12 (one pixel per
/// multicolour pixel) and whose height is a multiple of 21 is read as a grid
/// of sprite frames, left to right then top to bottom. Every pixel is snapped
/// to the nearest Pepto colour, a histogram over the whole strip proposes
/// BKG / COL1 ($D025) / COL2 ($D026), and the user confirms those plus the
/// HR/MC mode in a panel before anything touches the asset.
///
/// Three entry points:
///   scr_asset_spr_png_analyse(_asset_index)  file dialog, decode, open panel
///   scr_asset_spr_png_recount()              recompute per-frame mode / warnings
///   scr_asset_spr_png_commit()               build the SPRITE_SET from the panel state
///   scr_asset_spr_png_close()                free the preview sprite, close panel
///
/// Panel state lives in obj_asset_manager.pngstrip (initialised in Create).

function scr_asset_spr_png_analyse(_asset_index) {
    var _path = get_open_filename("PNG Sprite Strip|*.png", "");
    // Native dialog steals the key-up; see scr_spr64_import.
    io_clear();
    if (_path == "") exit;
    if (!file_exists(_path)) {
        scr_show_message("PNG STRIP: File not found:\n" + _path);
        exit;
    }

    var _spr = sprite_add(_path, 1, false, false, 0, 0);
    if (_spr < 0 || !sprite_exists(_spr)) {
        scr_show_message("PNG STRIP: Could not load PNG.");
        exit;
    }

    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);

    // ---- frame geometry ----
    // 24-wide frames are hires pixels; 12-wide frames are already one pixel
    // per multicolour pixel and are widened x2 on read.
    var _cell_w = 0;
    var _scale  = 1;
    if ((_w mod 24) == 0) {
        _cell_w = 24;
        _scale  = 1;
    } else if ((_w mod 12) == 0) {
        _cell_w = 12;
        _scale  = 2;
    }
    if (_cell_w == 0 || (_h mod 21) != 0) {
        sprite_delete(_spr);
        scr_show_message("PNG STRIP: Size " + string(_w) + "x" + string(_h)
            + " is not a sprite grid.\nWidth must be a multiple of 24 (or 12 for MC),\nheight a multiple of 21.");
        exit;
    }

    var _cols  = _w div _cell_w;
    var _rows  = _h div 21;
    var _count = _cols * _rows;
    if (_count > 64) {
        sprite_delete(_spr);
        scr_show_message("PNG STRIP: " + string(_count) + " frames — a sprite set holds 64.");
        exit;
    }

    // ---- read pixels into a Pepto index array, 24x21 per frame ----
    var _pep_r = array_create(16, 0);
    var _pep_g = array_create(16, 0);
    var _pep_b = array_create(16, 0);
    for (var _pi = 0; _pi < 16; _pi++) {
        var _pc = scr_c64_pepto_colour(_pi);
        _pep_r[_pi] = colour_get_red(_pc);
        _pep_g[_pi] = colour_get_green(_pc);
        _pep_b[_pi] = colour_get_blue(_pc);
    }

    var _surf = surface_create(_w, _h);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    draw_sprite(_spr, 0, 0, 0);
    surface_reset_target();

    var _px   = array_create(_count * 504, 0);   // 24*21 per frame
    var _hist = array_create(16, 0);
    // -1 marks transparent; it is resolved to BKG at commit time and never
    // votes in the histogram.
    for (var _fy = 0; _fy < _rows; _fy++) {
        for (var _fx = 0; _fx < _cols; _fx++) {
            var _fi   = _fy * _cols + _fx;
            var _base = _fi * 504;
            for (var _y = 0; _y < 21; _y++) {
                for (var _x = 0; _x < 24; _x++) {
                    var _sx = _fx * _cell_w + (_x div _scale);
                    var _sy = _fy * 21 + _y;
                    var _c  = surface_getpixel_ext(_surf, _sx, _sy);
                    var _a  = (_c >> 24) & 255;
                    var _idx = -1;
                    if (_a >= 128) {
                        var _r  = _c & 255;
                        var _g  = (_c >> 8) & 255;
                        var _b  = (_c >> 16) & 255;
                        var _best = 0;
                        var _bd   = 999999;
                        for (var _pi = 0; _pi < 16; _pi++) {
                            var _dr = _r - _pep_r[_pi];
                            var _dg = _g - _pep_g[_pi];
                            var _db = _b - _pep_b[_pi];
                            var _d  = _dr * _dr + _dg * _dg + _db * _db;
                            if (_d < _bd) {
                                _bd   = _d;
                                _best = _pi;
                            }
                        }
                        _idx = _best;
                        _hist[_best] += 1;
                    }
                    _px[_base + _y * 24 + _x] = _idx;
                }
            }
        }
    }
    surface_free(_surf);

    // ---- colour order by frequency, most common first ----
    var _order = [];
    for (var _pi = 0; _pi < 16; _pi++) {
        if (_hist[_pi] > 0) array_push(_order, _pi);
    }
    for (var _i = 0; _i < array_length(_order); _i++) {
        for (var _j = _i + 1; _j < array_length(_order); _j++) {
            if (_hist[_order[_j]] > _hist[_order[_i]]) {
                var _t = _order[_i]; _order[_i] = _order[_j]; _order[_j] = _t;
            }
        }
    }
    // A strip with transparency means the transparent colour IS the
    // background — put black first so BKG defaults to 0.
    var _has_alpha = false;
    for (var _i = 0; _i < array_length(_px); _i++) {
        if (_px[_i] == -1) { _has_alpha = true; break; }
    }
    if (_has_alpha) {
        var _o2 = [0];
        for (var _i = 0; _i < array_length(_order); _i++) {
            if (_order[_i] != 0) array_push(_o2, _order[_i]);
        }
        _order = _o2;
    }
    while (array_length(_order) < 3) {
        // pad with unused pens so the swatches always have something
        for (var _pi = 0; _pi < 16 && array_length(_order) < 3; _pi++) {
            var _dup = false;
            for (var _oi = 0; _oi < array_length(_order); _oi++) if (_order[_oi] == _pi) _dup = true;
            if (!_dup) array_push(_order, _pi);
        }
    }

    with (obj_asset_manager) {
        pngstrip.open    = true;
        pngstrip.asset   = _asset_index;
        pngstrip.path    = _path;
        pngstrip.spr     = _spr;
        pngstrip.w       = _w;
        pngstrip.h       = _h;
        pngstrip.cols    = _cols;
        pngstrip.rows    = _rows;
        pngstrip.count   = _count;
        pngstrip.cell_w  = _cell_w;
        pngstrip.px      = _px;
        pngstrip.hist    = _hist;
        pngstrip.order   = _order;
        pngstrip.bg      = _order[0];
        pngstrip.col1    = _order[1];
        pngstrip.col2    = _order[2];
        pngstrip.bg_i    = 0;
        pngstrip.col1_i  = 1;
        pngstrip.col2_i  = 2;
        pngstrip.mode    = 0;
        pngstrip.frame_mc = array_create(64, 0);
        pngstrip.frame_uc = array_create(64, 1);
        pngstrip.warn    = 0;
        pngstrip.hr_count = 0;
        pngstrip.mc_count = 0;
    }
    scr_asset_spr_png_recount();
}

/// Per-frame decision from the current BKG/COL1/COL2/mode:
///   AUTO  : a frame with one colour beyond BKG is hires, otherwise MC
///   HIRES : every non-BKG pixel is set, sprite colour = its most common colour
///   MC    : BKG->00, COL1->01, COL2->11, everything else -> 10 (sprite colour)
/// warn counts frames whose "everything else" is more than one colour.
function scr_asset_spr_png_recount() {
    with (obj_asset_manager) {
        var _p = pngstrip;
        _p.warn     = 0;
        _p.hr_count = 0;
        _p.mc_count = 0;
        for (var _fi = 0; _fi < _p.count; _fi++) {
            var _base = _fi * 504;
            var _cnt  = array_create(16, 0);
            for (var _i = 0; _i < 504; _i++) {
                var _c = _p.px[_base + _i];
                if (_c < 0) _c = _p.bg;
                _cnt[_c] += 1;
            }
            // colours present other than BKG
            var _non_bg = 0;
            var _extra  = 0;       // beyond BKG, COL1, COL2
            var _uc     = -1;
            var _uc_n   = 0;
            for (var _c = 0; _c < 16; _c++) {
                if (_cnt[_c] == 0 || _c == _p.bg) continue;
                _non_bg += 1;
                if (_c != _p.col1 && _c != _p.col2) {
                    _extra += 1;
                    if (_cnt[_c] > _uc_n) { _uc_n = _cnt[_c]; _uc = _c; }
                }
            }
            var _mc = 0;
            if (_p.mode == 1) {
                _mc = 0;
            } else if (_p.mode == 2) {
                _mc = 1;
            } else {
                if (_non_bg > 1) _mc = 1; else _mc = 0;
            }
            if (_mc == 0) {
                // hires: sprite colour = most common non-BKG colour of any kind
                _uc   = -1;
                _uc_n = 0;
                for (var _c = 0; _c < 16; _c++) {
                    if (_c == _p.bg) continue;
                    if (_cnt[_c] > _uc_n) { _uc_n = _cnt[_c]; _uc = _c; }
                }
                if (_non_bg > 1) _p.warn += 1;
                _p.hr_count += 1;
            } else {
                if (_extra > 1) _p.warn += 1;
                _p.mc_count += 1;
            }
            if (_uc < 0) _uc = 1;
            _p.frame_mc[_fi] = _mc;
            _p.frame_uc[_fi] = _uc;
        }
    }
}

function scr_asset_spr_png_close() {
    with (obj_asset_manager) {
        if (pngstrip.spr >= 0 && sprite_exists(pngstrip.spr)) sprite_delete(pngstrip.spr);
        pngstrip.spr   = -1;
        pngstrip.open  = false;
        pngstrip.asset = -1;
        pngstrip.px    = [];
    }
}

function scr_asset_spr_png_commit() {
    with (obj_asset_manager) {
        var _p = pngstrip;
        if (_p.asset < 0 || _p.asset >= ds_list_size(asset_list)) {
            scr_asset_spr_png_close();
            exit;
        }
        var _asset = ds_list_find_value(asset_list, _p.asset);
        if (_asset.type != "SPRITE_SET") {
            scr_asset_spr_png_close();
            exit;
        }

        var _used = clamp(_p.count, 1, 64);
        var _sprite_mcs = array_create(_used, 0);
        var _sprite_ucs = array_create(_used, 1);
        var _sprite_buf = buffer_create(_used * 64, buffer_fixed, 1);
        buffer_seek(_sprite_buf, buffer_seek_start, 0);

        for (var _fi = 0; _fi < _used; _fi++) {
            var _base = _fi * 504;
            var _mc   = _p.frame_mc[_fi];
            var _uc   = _p.frame_uc[_fi];
            _sprite_mcs[_fi] = _mc;
            _sprite_ucs[_fi] = _uc;

            for (var _y = 0; _y < 21; _y++) {
                for (var _bx = 0; _bx < 3; _bx++) {
                    var _val = 0;
                    if (_mc == 0) {
                        for (var _bit = 0; _bit < 8; _bit++) {
                            var _c = _p.px[_base + _y * 24 + _bx * 8 + _bit];
                            if (_c < 0) _c = _p.bg;
                            if (_c != _p.bg) _val = _val | (128 >> _bit);
                        }
                    } else {
                        for (var _pair = 0; _pair < 4; _pair++) {
                            var _x0 = _bx * 8 + _pair * 2;
                            var _ca = _p.px[_base + _y * 24 + _x0];
                            var _cb = _p.px[_base + _y * 24 + _x0 + 1];
                            if (_ca < 0) _ca = _p.bg;
                            if (_cb < 0) _cb = _p.bg;
                            // a hires-drawn pair may disagree; the non-BKG pixel wins
                            var _c = _ca;
                            if (_c == _p.bg) _c = _cb;
                            var _code = 0;
                            if (_c == _p.bg)          _code = 0;
                            else if (_c == _p.col1)   _code = 1;
                            else if (_c == _p.col2)   _code = 3;
                            else                      _code = 2;
                            _val = _val | (_code << (6 - _pair * 2));
                        }
                    }
                    buffer_write(_sprite_buf, buffer_u8, _val);
                }
            }
            buffer_write(_sprite_buf, buffer_u8, 0);   // byte 63 padding
        }

        // Hex blob + JSON in the same shape scr_asset_spr_import produces
        var _hex_blob = "";
        buffer_seek(_sprite_buf, buffer_seek_start, 0);
        repeat(_used * 64) {
            _hex_blob += decimal_to_hex(buffer_read(_sprite_buf, buffer_u8));
        }
        var _json = "[";
        for (var _si = 0; _si < _used; _si++) {
            var _bytes = "";
            for (var _bi = 0; _bi < 64; _bi++) {
                if (_bi > 0) _bytes += ",";
                _bytes += string(buffer_peek(_sprite_buf, _si * 64 + _bi, buffer_u8));
            }
            if (_si > 0) _json += ",";
            _json += "{\"b\":\"" + _bytes + "\",\"mc\":" + string(_sprite_mcs[_si]) + ",\"uc\":" + string(_sprite_ucs[_si]) + "}";
        }
        _json += "]";

        // Replace old caches
        if (variable_struct_exists(_asset.meta, "spr_sprites")) {
            var _old_len = array_length(_asset.meta.spr_sprites);
            for (var _si = 0; _si < _old_len; _si++) {
                if (_asset.meta.spr_sprites[_si] != -1 && sprite_exists(_asset.meta.spr_sprites[_si]))
                    sprite_delete(_asset.meta.spr_sprites[_si]);
            }
        }
        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf))
            surface_free(_asset.meta.preview_surf);
        if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);

        _asset.file   = _p.path;
        _asset.buffer = _sprite_buf;
        _asset.meta = {
            format      : "pngstrip",
            has_colour  : true,
            bg_col      : _p.bg,
            mc1_col     : _p.col1,
            mc2_col     : _p.col2,
            sprite_json : _json,
            sprite_mcs  : _sprite_mcs,
            sprite_ucs  : _sprite_ucs,
            found_count : _used,
            used_count  : _used,
            hex_blob    : _hex_blob,
            total_size  : _used * 64
        };

        scr_asset_spr_cache_sprites(_asset, true);
        global.undo_dirty = true;
        scr_asset_spr_png_close();
    }
}
