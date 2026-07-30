/// @function scr_spred64_v2_fx_flipy(_slot)
/// @desc Vertically flips the bits of the active slot in-place.
///       Operates on the V2 working bits[] array (not the asset buffer).
///       Sets the dirty flag and refreshes the slot's preview sprite.
///       FlipY is mode-agnostic: it swaps entire rows of 24 bits each,
///       so MC pair alignment is preserved automatically.
function scr_spred64_v2_fx_flipy(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        for (var _py = 0; _py < 10; _py++) {
            var _top_base = _bit_base + _py * 24;
            var _bot_base = _bit_base + (20 - _py) * 24;
            for (var _px = 0; _px < 24; _px++) {
                var _t = _v2.bits[_top_base + _px];
                var _b = _v2.bits[_bot_base + _px];
                _v2.bits[_top_base + _px] = _b;
                _v2.bits[_bot_base + _px] = _t;
            }
        }
        // Middle row (index 10) stays fixed — 21 is odd.
        _v2.dirty = true;
        scr_spred64_v2_invalidate_sot(_slot);
        if (surface_exists(_v2.edit_surface)) {
            surface_free(_v2.edit_surface);
        }
        _v2.edit_surface = -1;
        var _asset_idx = _v2.asset_index;
        if (_asset_idx >= 0 && _asset_idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, _asset_idx);
            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
        }
    }
}