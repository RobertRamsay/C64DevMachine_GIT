/// @function scr_spred64_v2_fx_fill(_slot)
/// @desc Fills the active slot with the V2 active PAINT colour.
///       MC mode: writes the appropriate bit pair (MC1=01, MC2=11, UC=10)
///       to every (even, odd) column pair so the fill renders correctly.
///       HR mode: sets every bit to 1 (drawing in UC).
///       Sets the dirty flag and refreshes the slot's preview sprite.
///       active_colour values: 1=MC1, 2=MC2, 3=UC.
function scr_spred64_v2_fx_fill(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);
        if (_is_mc) {
            // MC mode: determine the bit pair for the active paint colour.
            // active_colour: 1=MC1 -> pair (0,1), 2=MC2 -> pair (1,1),
            // 3=UC -> pair (1,0). BG (0,0) is unreachable here since BG
            // isn't a paint role — but if the user has somehow left
            // active_colour at 0 we default to UC.
            var _b0 = 1;
            var _b1 = 0;
            if (_v2.active_colour == 1) {
                _b0 = 0;
                _b1 = 1;
            } else if (_v2.active_colour == 2) {
                _b0 = 1;
                _b1 = 1;
            } else {
                // UC (active_colour 3) or fallback
                _b0 = 1;
                _b1 = 0;
            }
            for (var _py = 0; _py < 21; _py++) {
                var _row_base = _bit_base + _py * 24;
                for (var _px = 0; _px < 24; _px += 2) {
                    _v2.bits[_row_base + _px]     = _b0;
                    _v2.bits[_row_base + _px + 1] = _b1;
                }
            }
        } else {
            // HR mode: every bit set, draws in UC
            for (var _i = 0; _i < 504; _i++) {
                _v2.bits[_bit_base + _i] = 1;
            }
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