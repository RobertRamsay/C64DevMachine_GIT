/// @desc scr_asset_spr_cache_sprites(_asset)
/// V2-aware: rebuilds picker thumbnails (_asset.meta.spr_sprites[]) from
/// the asset's packed buffer + per-slot mc/uc state. Sizes to used_count —
/// does NOT allocate a full bank of 64.
function scr_asset_spr_cache_sprites(_asset, _force_rebuild = false) {
    show_debug_message("CACHE_SPRITES: entry name='" + string(_asset.name)
        + "' buf_size=" + string(buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : -1)
        + " force=" + string(_force_rebuild));

    if (!buffer_exists(_asset.buffer)) {
        show_debug_message("CACHE_SPRITES: bailing (no buffer)");
        exit;
    }

    // Determine how many sprites this asset actually has.
    var _used = 1;
    if (variable_struct_exists(_asset.meta, "used_count")) {
        _used = _asset.meta.used_count;
    }
    _used = clamp(_used, 1, 64);

    // spr_sprites: size to _used (not 64). Preserve existing entries.
    if (!variable_struct_exists(_asset.meta, "spr_sprites")) {
        _asset.meta.spr_sprites = array_create(_used, -1);
    }
    // Grow/shrink to _used, freeing any sprites that fall outside the new range.
    var _cur_len = array_length(_asset.meta.spr_sprites);
    if (_cur_len > _used) {
        for (var _i = _used; _i < _cur_len; _i++) {
            if (_asset.meta.spr_sprites[_i] != -1 && sprite_exists(_asset.meta.spr_sprites[_i])) {
                sprite_delete(_asset.meta.spr_sprites[_i]);
            }
        }
        array_resize(_asset.meta.spr_sprites, _used);
    } else if (_cur_len < _used) {
        for (var _i = _cur_len; _i < _used; _i++) {
            _asset.meta.spr_sprites[_i] = -1;
        }
    }

    // Ensure mc/uc/colour arrays. Sized to _used so we never carry blank-slot state.
    if (!variable_struct_exists(_asset.meta, "sprite_mcs")) _asset.meta.sprite_mcs = array_create(_used, 0);
    if (!variable_struct_exists(_asset.meta, "sprite_ucs")) _asset.meta.sprite_ucs = array_create(_used, 1);
    if (!variable_struct_exists(_asset.meta, "bg_col"))     _asset.meta.bg_col     = 0;
    if (!variable_struct_exists(_asset.meta, "mc1_col"))    _asset.meta.mc1_col    = 1;
    if (!variable_struct_exists(_asset.meta, "mc2_col"))    _asset.meta.mc2_col    = 2;

    var _bits   = scr_spred64_v2_unpack_bits(_asset);
    var _mcs    = _asset.meta.sprite_mcs;
    var _ucs    = _asset.meta.sprite_ucs;
    var _bg     = _asset.meta.bg_col;
    var _mc1    = _asset.meta.mc1_col;
    var _mc2    = _asset.meta.mc2_col;
    var _psize  = 2;
    var _sw     = 24 * _psize;
    var _sh     = 21 * _psize;
    var _bsz    = buffer_get_size(_asset.buffer);
    var _slots  = min(_used, floor(_bsz / 64));
    _slots      = max(_slots, 1);

    var _built = 0;
    for (var _slot = 0; _slot < _slots; _slot++) {

        // Skip if already cached and not forced
        if (!_force_rebuild &&
            _asset.meta.spr_sprites[_slot] != -1 &&
            sprite_exists(_asset.meta.spr_sprites[_slot])) {
            continue;
        }

        // Free old before replacing
        if (_asset.meta.spr_sprites[_slot] != -1 &&
            sprite_exists(_asset.meta.spr_sprites[_slot])) {
            sprite_delete(_asset.meta.spr_sprites[_slot]);
            _asset.meta.spr_sprites[_slot] = -1;
        }

        var _bit_base = _slot * 504;
        var _is_mc    = (_slot < array_length(_mcs)) ? (_mcs[_slot] == 1) : false;
        var _uc_pen   = (_slot < array_length(_ucs)) ? _ucs[_slot] : 1;

        var _surf = surface_create(_sw, _sh);
        surface_set_target(_surf);
        draw_clear_alpha(c_black, 0);

        if (_is_mc) {
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px += 2) {
                    var _b0 = _bits[_bit_base + _py * 24 + _px];
                    var _b1 = _bits[_bit_base + _py * 24 + _px + 1];
                    var _pair_col = -1;
                    if      (_b0 == 0 && _b1 == 1) _pair_col = _mc1;
                    else if (_b0 == 1 && _b1 == 0) _pair_col = _uc_pen;
                    else if (_b0 == 1 && _b1 == 1) _pair_col = _mc2;
                    if (_pair_col >= 0) {
                        draw_set_color(scr_c64_pepto_colour(_pair_col));
                        var _rx = _px * _psize;
                        var _ry = _py * _psize;
                        draw_rectangle(_rx, _ry, _rx + (_psize * 2), _ry + _psize, false);
                    }
                }
            }
        } else {
            draw_set_color(scr_c64_pepto_colour(_uc_pen));
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px++) {
                    if (_bits[_bit_base + _py * 24 + _px] == 1) {
                        var _rx = _px * _psize;
                        var _ry = _py * _psize;
                        draw_rectangle(_rx, _ry, _rx + _psize, _ry + _psize, false);
                    }
                }
            }
        }
        surface_reset_target();

        _asset.meta.spr_sprites[_slot] = sprite_create_from_surface(
            _surf, 0, 0, _sw, _sh, false, false, 0, 0);
        surface_free(_surf);
        _built++;
    }
    show_debug_message("CACHE_SPRITES: built " + string(_built) + " of " + string(_slots) + " slots (used_count=" + string(_used) + ")");
}