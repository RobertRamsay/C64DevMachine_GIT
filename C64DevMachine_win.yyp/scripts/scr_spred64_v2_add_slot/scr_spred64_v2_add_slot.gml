/// @function scr_spred64_v2_add_slot()
/// @desc Adds one new blank sprite slot to the open V2 asset, up to the
///       64-slot bank maximum. Grows used_count, clears the new slot's
///       working bits, ensures meta arrays cover it, refreshes the
///       thumbnail and selects the new slot. No-op at 64.
function scr_spred64_v2_add_slot() {
    with (obj_asset_manager) {

        if (!spred64_v2.active) exit;

        var _v2 = spred64_v2;

        // Already at the bank cap — nothing to add.
        if (_v2.used_count >= 64) {
            show_debug_message("ADD_SLOT: already at 64-slot cap");
            exit;
        }

        var _new_slot = _v2.used_count;   // 0-based index of the slot being added

        // Clear the working bits for the new slot (504 pixels).
        var _bit_base = _new_slot * 504;
        for (var _i = 0; _i < 504; _i++) {
            _v2.bits[_bit_base + _i] = 0;
        }

        // Default mode/colour for the new slot (HR, UC pen 1).
        _v2.sprite_modes[_new_slot] = 0;
        _v2.sprite_uc[_new_slot]    = 1;

        // Invalidate any stale ROT90 source-of-truth for this slot.
        _v2.rot_angle[_new_slot]     = 0;
        _v2.rot_sot_valid[_new_slot] = false;

        // Grow the count and select the new slot.
        _v2.used_count    = _new_slot + 1;
        _v2.selected_slot = _new_slot;

        // Mark dirty so the close-commit writes the new slot to the buffer.
        _v2.dirty = true;

        // Refresh the live asset's thumbnail array for the new slot.
        var _idx = _v2.asset_index;
        if (_idx >= 0 && _idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, _idx);

            // Ensure meta arrays cover the new slot before refresh reads them.
            if (variable_struct_exists(_asset.meta, "sprite_mcs")) {
                if (array_length(_asset.meta.sprite_mcs) <= _new_slot) {
                    array_resize(_asset.meta.sprite_mcs, _new_slot + 1);
                    _asset.meta.sprite_mcs[_new_slot] = 0;
                }
            }
            if (variable_struct_exists(_asset.meta, "sprite_ucs")) {
                if (array_length(_asset.meta.sprite_ucs) <= _new_slot) {
                    array_resize(_asset.meta.sprite_ucs, _new_slot + 1);
                    _asset.meta.sprite_ucs[_new_slot] = 1;
                }
            }
            if (variable_struct_exists(_asset.meta, "spr_sprites")) {
                if (array_length(_asset.meta.spr_sprites) <= _new_slot) {
                    array_resize(_asset.meta.spr_sprites, _new_slot + 1);
                    _asset.meta.spr_sprites[_new_slot] = -1;
                }
            }

            scr_spred64_v2_refresh_slot_sprite(_asset, _new_slot);
        }

        show_debug_message("ADD_SLOT: added slot " + string(_new_slot)
            + " (used_count now " + string(_v2.used_count) + ")");
    }
}