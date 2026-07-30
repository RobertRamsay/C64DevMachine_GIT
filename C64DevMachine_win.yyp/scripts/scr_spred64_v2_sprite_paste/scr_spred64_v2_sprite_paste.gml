/// @function scr_spred64_v2_sprite_paste()
/// @desc Pastes _v2.sprite_clipboard into the currently selected sprite
///       slot, replacing the slot's bits, mode (HR/MC), and UC colour.
///       No-op if clipboard is empty. Marks asset dirty, invalidates
///       any rotation SOT for the slot, and refreshes the picker thumb.
function scr_spred64_v2_sprite_paste() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _slot = _v2.selected_slot;
        if (_slot < 0 || _slot >= 64) exit;
        if (_v2.sprite_clipboard == -1) {
            show_debug_message("SPRED64 V2: paste — sprite clipboard empty");
            exit;
        }
        if (!is_array(_v2.sprite_clipboard)) exit;
        if (array_length(_v2.sprite_clipboard) != 504) {
            show_debug_message("SPRED64 V2: paste — clipboard size mismatch ("
                + string(array_length(_v2.sprite_clipboard)) + " bits)");
            exit;
        }
        // Write bits, mode, UC into the working slot
        var _base = _slot * 504;
        for (var _bi = 0; _bi < 504; _bi++) {
            _v2.bits[_base + _bi] = _v2.sprite_clipboard[_bi];
        }
        _v2.sprite_modes[_slot] = _v2.sprite_clipboard_mode;
        _v2.sprite_uc[_slot]    = _v2.sprite_clipboard_uc;
        _v2.dirty = true;
        // Editor surface & rotation SOT for this slot are stale now
        if (surface_exists(_v2.edit_surface)) {
            surface_free(_v2.edit_surface);
        }
        _v2.edit_surface = -1;
        scr_spred64_v2_invalidate_sot(_slot);
        // Refresh the picker thumbnail so the visual updates immediately.
        // The asset reference comes from the open asset_index.
        var _idx = _v2.asset_index;
        if (_idx >= 0 && _idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, _idx);
            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
        }
        show_debug_message("SPRED64 V2: pasted sprite into slot " + string(_slot)
            + " (mode=" + (_v2.sprite_clipboard_mode == 1 ? "MC" : "HR") + ")");
    }
}