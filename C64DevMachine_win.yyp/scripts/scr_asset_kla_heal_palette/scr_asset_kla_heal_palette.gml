function scr_asset_kla_heal_palette(_asset) {
    if (!variable_struct_exists(_asset.meta, "preview_surf")) return;
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _surf = _asset.meta.preview_surf;
    var _pepto_r = array_create(16, 0);
    var _pepto_g = array_create(16, 0);
    var _pepto_b = array_create(16, 0);
    var _color_hash = {};
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pepto_r[_c] = color_get_red(_col);
        _pepto_g[_c] = color_get_green(_col);
        _pepto_b[_c] = color_get_blue(_col);
        var _key = (_pepto_r[_c] << 16) | (_pepto_g[_c] << 8) | _pepto_b[_c];
        _color_hash[$ _key] = _c;
    }
    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    var _changed = false;
    // PASS 1 — snap every pixel to nearest exact Pepto RGB
    for (var _i = 0; _i < 320 * 200 * 4; _i += 4) {
        var _r = buffer_peek(_buf, _i,     buffer_u8);
        var _g = buffer_peek(_buf, _i + 1, buffer_u8);
        var _b = buffer_peek(_buf, _i + 2, buffer_u8);
        var _key = (_r << 16) | (_g << 8) | _b;
        var _idx = _color_hash[$ _key];
        if (_idx == undefined) {
            var _best = 0;
            var _min_dist = 999999;
            for (var _p = 0; _p < 16; _p++) {
                var _dist = abs(_r - _pepto_r[_p]) + abs(_g - _pepto_g[_p]) + abs(_b - _pepto_b[_p]);
                if (_dist < _min_dist) {
                    _min_dist = _dist;
                    _best = _p;
                }
            }
            _idx = _best;
        }
        if (_r != _pepto_r[_idx] || _g != _pepto_g[_idx] || _b != _pepto_b[_idx]) {
            buffer_poke(_buf, _i,     buffer_u8, _pepto_r[_idx]);
            buffer_poke(_buf, _i + 1, buffer_u8, _pepto_g[_idx]);
            buffer_poke(_buf, _i + 2, buffer_u8, _pepto_b[_idx]);
            buffer_poke(_buf, _i + 3, buffer_u8, 255);
            _changed = true;
        }
    }
    // PASS 2 — force the right pixel of every MC pair to match the left.
    // HiRes pixels are independently addressable (no pairing), so this pass
    // is skipped there — forcing pairs would silently merge detail.
    if (!_is_hires) {
        for (var _py = 0; _py < 200; _py++) {
            for (var _px = 0; _px < 320; _px += 2) {
                var _off_l = (_py * 320 + _px) * 4;
                var _off_r = _off_l + 4;
                var _lr = buffer_peek(_buf, _off_l,     buffer_u8);
                var _lg = buffer_peek(_buf, _off_l + 1, buffer_u8);
                var _lb = buffer_peek(_buf, _off_l + 2, buffer_u8);
                var _rr = buffer_peek(_buf, _off_r,     buffer_u8);
                var _rg = buffer_peek(_buf, _off_r + 1, buffer_u8);
                var _rb = buffer_peek(_buf, _off_r + 2, buffer_u8);
                if (_rr != _lr || _rg != _lg || _rb != _lb) {
                    buffer_poke(_buf, _off_r,     buffer_u8, _lr);
                    buffer_poke(_buf, _off_r + 1, buffer_u8, _lg);
                    buffer_poke(_buf, _off_r + 2, buffer_u8, _lb);
                    buffer_poke(_buf, _off_r + 3, buffer_u8, 255);
                    _changed = true;
                }
            }
        }
    }
    if (_changed) buffer_set_surface(_buf, _surf, 0);
    buffer_delete(_buf);
}