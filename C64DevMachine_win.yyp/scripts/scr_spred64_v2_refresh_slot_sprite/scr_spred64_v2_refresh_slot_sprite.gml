/// @function scr_spred64_v2_refresh_slot_sprite(_asset, _slot)
/// @desc Rebuilds the single GameMaker sprite cached in
///       _asset.meta.spr_sprites[_slot] from the current working bit
///       array, using the V2 working colour/mode state. Builds at the
///       same 2x scale used by scr_asset_spr_cache_sprites so the
///       picker thumbnails look identical to a SPRED64-imported asset.
function scr_spred64_v2_refresh_slot_sprite(_asset, _slot) {

    with (obj_asset_manager) {

        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;

        var _v2 = spred64_v2;

        // Ensure spr_sprites array exists and is long enough for _slot.
        // Arrays are sized to used_count, so grow on demand rather than
        // assuming a full 64-length bank.
        if (!variable_struct_exists(_asset.meta, "spr_sprites")) {
            _asset.meta.spr_sprites = array_create(_slot + 1, -1);
        } else if (array_length(_asset.meta.spr_sprites) <= _slot) {
            var _old_len = array_length(_asset.meta.spr_sprites);
            array_resize(_asset.meta.spr_sprites, _slot + 1);
            for (var _gi = _old_len; _gi <= _slot; _gi++) {
                _asset.meta.spr_sprites[_gi] = -1;
            }
        }

        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);
        var _uc_pen   = _v2.sprite_uc[_slot];
        var _bg_pen   = _v2.bg_col;
        var _mc1_pen  = _v2.mc1_col;
        var _mc2_pen  = _v2.mc2_col;

        // 2x scale to match scr_asset_spr_cache_sprites convention
        var _psize = 2;
        var _sw    = 24 * _psize; // 48
        var _sh    = 21 * _psize; // 42

        var _surf = surface_create(_sw, _sh);
        surface_set_target(_surf);
        // BG pixels are transparent on the sprite — the compositor's
        // global BG fill (or in single-slot views, whatever is behind)
        // shows through. Matches real C64 sprite transparency.
        draw_clear_alpha(c_black, 0);

        if (_is_mc) {
            // MC: each bit pair makes a 2-pixel-wide pixel
            // At 2x scale, that's 4px wide x 2px tall on the surface
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px += 2) {
                    var _b0 = _v2.bits[_bit_base + _py * 24 + _px];
                    var _b1 = _v2.bits[_bit_base + _py * 24 + _px + 1];
                    var _pair_col = -1;
                    if (_b0 == 0 && _b1 == 0) {
                        _pair_col = -1; // BG (already cleared)
                    } else if (_b0 == 0 && _b1 == 1) {
                        _pair_col = _mc1_pen;
                    } else if (_b0 == 1 && _b1 == 0) {
                        _pair_col = _uc_pen;
                    } else if (_b0 == 1 && _b1 == 1) {
                        _pair_col = _mc2_pen;
                    }
                    if (_pair_col >= 0) {
                        draw_set_color(scr_c64_pepto_colour(_pair_col));
                        var _rx = _px * _psize;
                        var _ry = _py * _psize;
                        draw_rectangle(_rx, _ry,
                                       _rx + (_psize * 2), _ry + _psize,
                                       false);
                    }
                }
            }
        } else {
            // HR: 1 bit per pixel, at 2x = 2px x 2px block
            draw_set_color(scr_c64_pepto_colour(_uc_pen));
            for (var _py = 0; _py < 21; _py++) {
                for (var _px = 0; _px < 24; _px++) {
                    if (_v2.bits[_bit_base + _py * 24 + _px] == 1) {
                        var _rx = _px * _psize;
                        var _ry = _py * _psize;
                        draw_rectangle(_rx, _ry,
                                       _rx + _psize, _ry + _psize,
                                       false);
                    }
                }
            }
        }
        surface_reset_target();

        // Free old sprite, replace with new
        if (_asset.meta.spr_sprites[_slot] != -1
        && sprite_exists(_asset.meta.spr_sprites[_slot])) {
            sprite_delete(_asset.meta.spr_sprites[_slot]);
        }
        _asset.meta.spr_sprites[_slot] = sprite_create_from_surface(
            _surf, 0, 0, _sw, _sh, false, false, 0, 0);

        surface_free(_surf);

        // Keep used_count honest
        if (_slot >= _v2.used_count) {
            _v2.used_count = _slot + 1;
        }
    }
}