/// @function scr_spred64_v2_sprite_copy()
/// @desc Copies the currently selected sprite's bits, mode (HR/MC), and
///       UC colour into _v2.sprite_clipboard. The clipboard holds one
///       sprite at a time; subsequent copies replace it.
function scr_spred64_v2_sprite_copy() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        var _v2   = spred64_v2;
        var _slot = _v2.selected_slot;
        if (_slot < 0 || _slot >= 64) exit;
        var _base = _slot * 504;
        var _clip = array_create(504, 0);
        for (var _bi = 0; _bi < 504; _bi++) {
            _clip[_bi] = _v2.bits[_base + _bi];
        }
        _v2.sprite_clipboard      = _clip;
        _v2.sprite_clipboard_mode = _v2.sprite_modes[_slot];
        _v2.sprite_clipboard_uc   = _v2.sprite_uc[_slot];
        show_debug_message("SPRED64 V2: copied sprite slot " + string(_slot)
            + " (mode=" + (_v2.sprite_clipboard_mode == 1 ? "MC" : "HR")
            + ", uc=" + string(_v2.sprite_clipboard_uc) + ")");
    }
}