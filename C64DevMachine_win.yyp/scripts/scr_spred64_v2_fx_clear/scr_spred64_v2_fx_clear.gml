/// @function scr_spred64_v2_fx_clear(_slot)
/// @desc Clears the active slot's bits[] to all zeros — every pixel becomes
///       BG. Sets the dirty flag and refreshes the slot's preview sprite.
function scr_spred64_v2_fx_clear(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        for (var _i = 0; _i < 504; _i++) {
            _v2.bits[_bit_base + _i] = 0;
        }
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