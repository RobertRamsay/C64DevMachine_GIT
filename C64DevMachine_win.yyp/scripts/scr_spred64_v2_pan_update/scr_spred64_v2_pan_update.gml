/// @function scr_spred64_v2_pan_update(_asset, _mx, _my, _cell_size)
/// @desc Per-frame pan update. Accumulates mouse delta and triggers
///       sprite shifts whenever the accumulator crosses one step threshold
///       in either axis. Step thresholds:
///         HR: 1 C64 px = _cell_size screen px in both axes
///         MC: X step = 2 C64 px = 2*_cell_size screen px; Y step unchanged
///       Caller must have already verified pan_active is true.
function scr_spred64_v2_pan_update(_asset, _mx, _my, _cell_size) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (!spred64_v2.pan_active) exit;
        var _v2 = spred64_v2;
        var _slot = _v2.pan_slot;
        if (_slot < 0 || _slot >= 64) {
            _v2.pan_active = false;
            exit;
        }
        var _is_mc = (_v2.sprite_modes[_slot] == 1);
        // Frame delta
        var _frame_dx = _mx - _v2.pan_last_mx;
        var _frame_dy = _my - _v2.pan_last_my;
        _v2.pan_last_mx = _mx;
        _v2.pan_last_my = _my;
        _v2.pan_accum_dx += _frame_dx;
        _v2.pan_accum_dy += _frame_dy;
        // Step thresholds in screen pixels
        var _step_x_screen = _is_mc ? (_cell_size * 2) : _cell_size;
        var _step_y_screen = _cell_size;
        // Bit-step amounts (per shift call)
        var _x_step_bits = _is_mc ? 2 : 1;
        var _y_step_bits = 1;
        // Trigger shifts while the accumulator exceeds the threshold
        var _any_shift = false;
        while (_v2.pan_accum_dx >= _step_x_screen) {
            scr_spred64_v2_pan_shift(_slot, _x_step_bits, 0);
            _v2.pan_accum_dx -= _step_x_screen;
            _any_shift = true;
        }
        while (_v2.pan_accum_dx <= -_step_x_screen) {
            scr_spred64_v2_pan_shift(_slot, -_x_step_bits, 0);
            _v2.pan_accum_dx += _step_x_screen;
            _any_shift = true;
        }
        while (_v2.pan_accum_dy >= _step_y_screen) {
            scr_spred64_v2_pan_shift(_slot, 0, _y_step_bits);
            _v2.pan_accum_dy -= _step_y_screen;
            _any_shift = true;
        }
        while (_v2.pan_accum_dy <= -_step_y_screen) {
            scr_spred64_v2_pan_shift(_slot, 0, -_y_step_bits);
            _v2.pan_accum_dy += _step_y_screen;
            _any_shift = true;
        }
        if (_any_shift) {
            _v2.dirty = true;
            scr_spred64_v2_invalidate_sot(_slot);
            if (surface_exists(_v2.edit_surface)) {
                surface_free(_v2.edit_surface);
            }
            _v2.edit_surface = -1;
            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
        }
    }
}