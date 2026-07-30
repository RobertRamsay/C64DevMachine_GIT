/// @function scr_spred64_v2_fx_flipx(_slot)
/// @desc Horizontally flips the bits of the active slot in-place.
///       Operates on the V2 working bits[] array (not the asset buffer).
///       Sets the dirty flag and refreshes the slot's preview sprite.
///       MC mode: bit pairs at (0,1) (2,3) ... must swap as PAIRS, not as
///       individual bits, or the pair's MSB/LSB get scrambled and the
///       colour mapping (MC1/MC2/UC) is corrupted.
function scr_spred64_v2_fx_flipx(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);
        if (_is_mc) {
            // 12 pairs per row, flip pair order, keep pair internal bit order
            for (var _py = 0; _py < 21; _py++) {
                for (var _pair_i = 0; _pair_i < 6; _pair_i++) {
                    var _lx   = _pair_i * 2;
                    var _rx   = (11 - _pair_i) * 2;
                    if (_lx >= _rx) {
                        break;
                    }
                    var _row_base = _bit_base + _py * 24;
                    var _l0 = _v2.bits[_row_base + _lx];
                    var _l1 = _v2.bits[_row_base + _lx + 1];
                    var _r0 = _v2.bits[_row_base + _rx];
                    var _r1 = _v2.bits[_row_base + _rx + 1];
                    _v2.bits[_row_base + _lx]     = _r0;
                    _v2.bits[_row_base + _lx + 1] = _r1;
                    _v2.bits[_row_base + _rx]     = _l0;
                    _v2.bits[_row_base + _rx + 1] = _l1;
                }
            }
        } else {
            // HR mode: 24 individual bits per row, flip in place
            for (var _py = 0; _py < 21; _py++) {
                var _row_base = _bit_base + _py * 24;
                for (var _px = 0; _px < 12; _px++) {
                    var _l = _v2.bits[_row_base + _px];
                    var _r = _v2.bits[_row_base + (23 - _px)];
                    _v2.bits[_row_base + _px]        = _r;
                    _v2.bits[_row_base + (23 - _px)] = _l;
                }
            }
        }
        _v2.dirty = true;
        scr_spred64_v2_invalidate_sot(_slot);
        if (surface_exists(_v2.edit_surface)) {
            surface_free(_v2.edit_surface);
        }
        _v2.edit_surface = -1;
        // Refresh picker thumbnail to reflect the change
        var _asset_idx = _v2.asset_index;
        if (_asset_idx >= 0 && _asset_idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, _asset_idx);
            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
        }
    }
}