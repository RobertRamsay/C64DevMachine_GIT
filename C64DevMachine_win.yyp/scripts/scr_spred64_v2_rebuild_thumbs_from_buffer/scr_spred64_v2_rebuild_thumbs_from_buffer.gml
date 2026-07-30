/// @function scr_spred64_v2_rebuild_thumbs_from_buffer(_asset)
/// @desc Builds all picker thumbnails (_asset.meta.spr_sprites[64]) by
///       reading bits directly from the asset's buffer and rendering at
///       2x scale. Independent of V2 — usable whenever the regular sprite
///       cache hasn't run (e.g. on workspace load where the asset has no
///       source file).
function scr_spred64_v2_rebuild_thumbs_from_buffer(_asset) {

    if (!buffer_exists(_asset.buffer)) exit;
    if (!variable_struct_exists(_asset, "meta")) exit;

    // Ensure required meta fields exist with safe defaults
    if (!variable_struct_exists(_asset.meta, "spr_sprites")) {
        _asset.meta.spr_sprites = array_create(64, -1);
    }
    if (!variable_struct_exists(_asset.meta, "sprite_mcs")) {
        _asset.meta.sprite_mcs = array_create(64, 0);
    }
    if (!variable_struct_exists(_asset.meta, "sprite_ucs")) {
        _asset.meta.sprite_ucs = array_create(64, 1);
    }
    if (!variable_struct_exists(_asset.meta, "bg_col"))  _asset.meta.bg_col  = 0;
    if (!variable_struct_exists(_asset.meta, "mc1_col")) _asset.meta.mc1_col = 1;
    if (!variable_struct_exists(_asset.meta, "mc2_col")) _asset.meta.mc2_col = 2;

    var _bsz   = buffer_get_size(_asset.buffer);
    var _psize = 2;
    var _sw    = 24 * _psize;
    var _sh    = 21 * _psize;

    var _rt_used    = clamp(variable_struct_exists(_asset.meta, "used_count") ? _asset.meta.used_count : 1, 1, 64);
    var _rt_mcs_len = array_length(_asset.meta.sprite_mcs);
    var _rt_ucs_len = array_length(_asset.meta.sprite_ucs);
    for (var _slot = 0; _slot < _rt_used; _slot++) {

        var _byte_base = _slot * 64;
        if (_byte_base >= _bsz) {
            // Out of buffer — leave slot empty
            if (_asset.meta.spr_sprites[_slot] != -1
            && sprite_exists(_asset.meta.spr_sprites[_slot])) {
                sprite_delete(_asset.meta.spr_sprites[_slot]);
            }
            _asset.meta.spr_sprites[_slot] = -1;
            continue;
        }

        // Working state for this slot
        var _is_mc   = (_slot < _rt_mcs_len) ? (_asset.meta.sprite_mcs[_slot] == 1) : false;
        var _uc_pen  = (_slot < _rt_ucs_len) ? _asset.meta.sprite_ucs[_slot] : 1;
        var _bg_pen  = _asset.meta.bg_col;
        var _mc1_pen = _asset.meta.mc1_col;
        var _mc2_pen = _asset.meta.mc2_col;

        // Build surface
        var _surf = surface_create(_sw, _sh);
        surface_set_target(_surf);
        draw_clear(scr_c64_pepto_colour(_bg_pen));

        // Unpack 63 pixel-data bytes of this slot, one row at a time
        for (var _py = 0; _py < 21; _py++) {
            for (var _bx = 0; _bx < 3; _bx++) {
                var _byte_off = _byte_base + _py * 3 + _bx;
                if (_byte_off >= _bsz) break;
                var _val = buffer_peek(_asset.buffer, _byte_off, buffer_u8);

                if (_is_mc) {
                    // 4 MC pairs per byte (2 bits each), high pair leftmost
                    for (var _pi = 0; _pi < 4; _pi++) {
                        var _shift = 6 - _pi * 2;
                        var _pair  = (_val >> _shift) & 3;
                        if (_pair == 0) continue; // BG (already cleared)
                        var _col;
                        if (_pair == 1) {
                            _col = _mc1_pen;
                        } else if (_pair == 2) {
                            _col = _uc_pen;
                        } else {
                            _col = _mc2_pen;
                        }
                        draw_set_color(scr_c64_pepto_colour(_col));
                        var _px = _bx * 8 + _pi * 2;
                        var _rx = _px * _psize;
                        var _ry = _py * _psize;
                        draw_rectangle(_rx, _ry,
                                       _rx + (_psize * 2), _ry + _psize,
                                       false);
                    }
                } else {
                    // 8 HR pixels per byte, MSB leftmost
                    draw_set_color(scr_c64_pepto_colour(_uc_pen));
                    for (var _bp = 0; _bp < 8; _bp++) {
                        if (_val & (128 >> _bp)) {
                            var _px = _bx * 8 + _bp;
                            var _rx = _px * _psize;
                            var _ry = _py * _psize;
                            draw_rectangle(_rx, _ry,
                                           _rx + _psize, _ry + _psize,
                                           false);
                        }
                    }
                }
            }
        }

        surface_reset_target();

        // Replace existing sprite
        if (_asset.meta.spr_sprites[_slot] != -1
        && sprite_exists(_asset.meta.spr_sprites[_slot])) {
            sprite_delete(_asset.meta.spr_sprites[_slot]);
        }
        _asset.meta.spr_sprites[_slot] = sprite_create_from_surface(
            _surf, 0, 0, _sw, _sh, false, false, 0, 0);

        surface_free(_surf);
    }
}