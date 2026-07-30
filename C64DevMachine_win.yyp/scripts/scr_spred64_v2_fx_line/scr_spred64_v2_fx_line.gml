/// @function scr_spred64_v2_fx_line(_slot, _x0, _y0, _x1, _y1)
/// @desc Draws a 1-pixel-wide line on the slot's bits[] from (x0,y0) to
///       (x1,y1) using Bresenham's algorithm. Respects MC mode — in MC
///       mode, x coordinates snap to even (pair-aligned) and each plotted
///       pixel writes a 2-bit pair according to the active colour.
///       Coordinates are in C64 sprite pixels (24x21 grid).
function scr_spred64_v2_fx_line(_slot, _x0, _y0, _x1, _y1) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2    = spred64_v2;
        var _base  = _slot * 504;
        var _is_mc = (_v2.sprite_modes[_slot] == 1);
        // MC mode — snap endpoints to MC pair boundaries (even x)
        if (_is_mc) {
            _x0 = _x0 - (_x0 mod 2);
            _x1 = _x1 - (_x1 mod 2);
        }
        // Bresenham — plots each point along the line
        var _dx = abs(_x1 - _x0);
        var _dy = abs(_y1 - _y0);
        // MC mode uses pair-stride for X so the line doesn't double-up cells
        var _sx_step = _is_mc ? 2 : 1;
        var _sx = (_x0 < _x1) ? _sx_step : -_sx_step;
        var _sy = (_y0 < _y1) ? 1 : -1;
        // In MC mode we step X in pairs, so adjust _dx accordingly for slope
        var _dx_eff = _is_mc ? floor(_dx / 2) : _dx;
        var _err = _dx_eff - _dy;
        var _cx = _x0;
        var _cy = _y0;
        // Safety cap to prevent infinite loops on malformed inputs
        var _safety = 64;
        while (_safety > 0) {
            _safety--;
            // Plot at (_cx, _cy) if in bounds
            if (_cx >= 0 && _cx < 24 && _cy >= 0 && _cy < 21) {
                var _idx = _base + _cy * 24 + _cx;
                if (_is_mc) {
                    var _new_b0 = 0;
                    var _new_b1 = 0;
                    switch (_v2.active_colour) {
                        case 1: _new_b0 = 0; _new_b1 = 1; break; // MC1
                        case 2: _new_b0 = 1; _new_b1 = 1; break; // MC2
                        case 3: _new_b0 = 1; _new_b1 = 0; break; // UC
                        default: _new_b0 = 0; _new_b1 = 0; break;
                    }
                    _v2.bits[_idx]     = _new_b0;
                    _v2.bits[_idx + 1] = _new_b1;
                } else {
                    // HR: just set the bit (active_colour 3 = paint UC)
                    _v2.bits[_idx] = 1;
                }
            }
            // End condition — reached (x1, y1)
            if (_cx == _x1 && _cy == _y1) break;
            var _e2 = _err * 2;
            if (_e2 > -_dy) {
                _err -= _dy;
                _cx += _sx;
            }
            if (_e2 < _dx_eff) {
                _err += _dx_eff;
                _cy += _sy;
            }
        }
        _v2.dirty = true;
        scr_spred64_v2_invalidate_sot(_slot);
        // Refresh the picker thumbnail for this slot
        var _idx = _v2.asset_index;
        if (_idx >= 0 && _idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, _idx);
            scr_spred64_v2_refresh_slot_sprite(_asset, _slot);
        }
    }
}