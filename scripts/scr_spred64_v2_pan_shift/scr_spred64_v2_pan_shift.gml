/// @function scr_spred64_v2_pan_shift(_slot, _dx, _dy)
/// @desc Shifts the active slot's bits[] by (_dx, _dy) C64 pixels with
///       wraparound. Used by the pan-drag handler; each call advances the
///       sprite by exactly one minimum step in the requested direction.
///       _dx values: -1 / 0 / +1 (HR), -2 / 0 / +2 (MC, in raw bit cols)
///       _dy values: -1 / 0 / +1 in both modes.
///       Wraparound: pixels going off one edge appear on the opposite edge.
///       Does NOT set dirty or refresh — the caller batches these per frame
///       so multi-step shifts only trigger one refresh.
function scr_spred64_v2_pan_shift(_slot, _dx, _dy) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        if (_dx == 0 && _dy == 0) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        // Copy current bits into a temp buffer, then write back shifted
        var _src = array_create(504, 0);
        for (var _i = 0; _i < 504; _i++) {
            _src[_i] = _v2.bits[_bit_base + _i];
        }
        for (var _y = 0; _y < 21; _y++) {
            // Source row after Y-shift with wraparound
            var _sy = ((_y - _dy) mod 21 + 21) mod 21;
            for (var _x = 0; _x < 24; _x++) {
                var _sx = ((_x - _dx) mod 24 + 24) mod 24;
                _v2.bits[_bit_base + _y * 24 + _x] = _src[_sy * 24 + _sx];
            }
        }
    }
}