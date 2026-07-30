/// @function scr_spred64_v2_remove_last_slot()
/// @desc Removes the trailing sprite slot from the V2 editor working state.
///       Only valid when used_count > 1 AND the last slot is blank (no set
///       bits) — matching the "EMPTY, ALT-click to remove" affordance. The
///       packed buffer and meta arrays are re-trimmed to the new used_count
///       on commit (repack_bits + close), so this only touches working state.
function scr_spred64_v2_remove_last_slot() {
    with (obj_asset_manager) {
        var _v2 = spred64_v2;
        if (!_v2.active) exit;

        var _used = clamp(_v2.used_count, 1, 64);
        if (_used <= 1) {
            show_debug_message("REMOVE_LAST_SLOT: refused — only one slot left");
            exit;
        }

        var _last = _used - 1;

        // Guard: last slot must be blank (no set bits across its 504 range).
        var _base  = _last * 504;
        var _blank = true;
        for (var _b = 0; _b < 504; _b++) {
            if (_v2.bits[_base + _b] == 1) {
                _blank = false;
                break;
            }
        }
        if (!_blank) {
            show_debug_message("REMOVE_LAST_SLOT: refused — slot " + string(_last) + " is not blank");
            exit;
        }

        // Clear the removed slot's working state so a later re-add starts clean.
        for (var _c = 0; _c < 504; _c++) {
            _v2.bits[_base + _c] = 0;
        }
        _v2.sprite_modes[_last] = 0;
        _v2.sprite_uc[_last]    = 1;
        // Clear any batch-select membership on the removed slot so the cyan
        // bracket doesn't appear to "jump" to whatever slot later inherits
        // this index. The draw/apply loops already guard against out-of-range
        // via used_count; this just keeps the visible set tidy.
        _v2.multi_select[_last] = false;
        // Drop the count.
        _v2.used_count = _used - 1;

        // If the removed slot was selected, fall back to the new last slot.
        if (_v2.selected_slot >= _v2.used_count) {
            _v2.selected_slot = _v2.used_count - 1;
            if (surface_exists(_v2.edit_surface)) {
                surface_free(_v2.edit_surface);
            }
            _v2.edit_surface = -1;
            _v2.fill_armed    = false;
            _v2.line_armed    = false;
            _v2.line_anchor_x = -1;
            _v2.line_anchor_y = -1;
        }

        _v2.dirty = true;
        show_debug_message("REMOVE_LAST_SLOT: removed slot " + string(_last)
            + " (used_count now " + string(_v2.used_count) + ")");
    }
}