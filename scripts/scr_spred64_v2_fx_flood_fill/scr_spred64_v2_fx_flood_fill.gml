/// @function scr_spred64_v2_fx_flood_fill(_slot, _seed_x, _seed_y)
/// @desc Flood-fills the active slot starting at (_seed_x, _seed_y), using
///       the V2 active paint colour. 4-way connectivity in HR mode; in MC
///       mode each bit pair is treated as one "wide pixel" and flood
///       operates on pair coordinates (12 wide x 21 tall).
///
///       Seed coordinates are in C64 PIXEL space (0..23, 0..20). In MC mode
///       the seed is snapped to its containing pair (even x).
///
///       In HR mode: matches existing bits equal to the seed's bit value
///       (so clicking a BG pixel fills the BG region; clicking a UC pixel
///       fills the UC region).
///
///       In MC mode: matches existing pairs equal to the seed pair's value
///       (BG/MC1/UC/MC2 regions are all individually floodable). The new
///       pair value comes from V2 active_colour (1=MC1, 2=MC2, 3=UC).
///
///       Uses an iterative stack-based flood (no recursion blowup on a
///       fully-uniform sprite of 504 pixels).
function scr_spred64_v2_fx_flood_fill(_slot, _seed_x, _seed_y) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        if (_seed_x < 0 || _seed_x >= 24) exit;
        if (_seed_y < 0 || _seed_y >= 21) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);
        if (_is_mc) {
            // ----- MC MODE: flood on pair coordinates (12 wide x 21 tall) -----
            // Snap seed_x to the containing pair (even)
            var _seed_px = _seed_x - (_seed_x mod 2);
            var _seed_pair_x = _seed_px div 2;
            // Read the seed pair value (two bits) — this is the "old colour" we replace
            var _old_b0 = _v2.bits[_bit_base + _seed_y * 24 + _seed_px];
            var _old_b1 = _v2.bits[_bit_base + _seed_y * 24 + _seed_px + 1];
            // Resolve new pair from active_colour
            var _new_b0 = 1;
            var _new_b1 = 0;
            if (_v2.active_colour == 1) {
                _new_b0 = 0;
                _new_b1 = 1;
            } else if (_v2.active_colour == 2) {
                _new_b0 = 1;
                _new_b1 = 1;
            } else {
                // UC (active_colour 3) or fallback
                _new_b0 = 1;
                _new_b1 = 0;
            }
            // No-op if seed already matches target
            if (_old_b0 == _new_b0 && _old_b1 == _new_b1) {
                _v2.fill_armed = false;
                exit;
            }
            // Iterative flood on pair coords. Stack holds [pair_x, y] entries.
            // visited[] tracks which pair-cells have been pushed (12 x 21 = 252).
            var _visited = array_create(12 * 21, 0);
            var _stack   = [];
            array_push(_stack, [_seed_pair_x, _seed_y]);
            _visited[_seed_pair_x + _seed_y * 12] = 1;
            while (array_length(_stack) > 0) {
                var _node = array_pop(_stack);
                var _px = _node[0];
                var _py = _node[1];
                // Write the new pair at this pair coord (global col = _px * 2)
                var _glob_col = _px * 2;
                _v2.bits[_bit_base + _py * 24 + _glob_col]     = _new_b0;
                _v2.bits[_bit_base + _py * 24 + _glob_col + 1] = _new_b1;
                // 4-way neighbours in pair space
                var _nbrs = [
                    [_px - 1, _py],
                    [_px + 1, _py],
                    [_px, _py - 1],
                    [_px, _py + 1]
                ];
                for (var _ni = 0; _ni < 4; _ni++) {
                    var _nx = _nbrs[_ni][0];
                    var _ny = _nbrs[_ni][1];
                    if (_nx < 0 || _nx >= 12 || _ny < 0 || _ny >= 21) {
                        continue;
                    }
                    if (_visited[_nx + _ny * 12]) {
                        continue;
                    }
                    var _ngc = _nx * 2;
                    var _nb0 = _v2.bits[_bit_base + _ny * 24 + _ngc];
                    var _nb1 = _v2.bits[_bit_base + _ny * 24 + _ngc + 1];
                    if (_nb0 == _old_b0 && _nb1 == _old_b1) {
                        _visited[_nx + _ny * 12] = 1;
                        array_push(_stack, [_nx, _ny]);
                    }
                }
            }
        } else {
            // ----- HR MODE: flood on individual bits (24 wide x 21 tall) -----
            var _old_bit = _v2.bits[_bit_base + _seed_y * 24 + _seed_x];
            // New bit: 1 = paint (UC pen), 0 = clear (BG)
            // Active paint role in HR is always UC, so painting writes 1.
            // If user is flood-filling on a UC pixel (old_bit=1), no-op.
            var _new_bit = 1;
            if (_old_bit == _new_bit) {
                _v2.fill_armed = false;
                exit;
            }
            var _visited = array_create(24 * 21, 0);
            var _stack   = [];
            array_push(_stack, [_seed_x, _seed_y]);
            _visited[_seed_x + _seed_y * 24] = 1;
            while (array_length(_stack) > 0) {
                var _node = array_pop(_stack);
                var _px = _node[0];
                var _py = _node[1];
                _v2.bits[_bit_base + _py * 24 + _px] = _new_bit;
                var _nbrs = [
                    [_px - 1, _py],
                    [_px + 1, _py],
                    [_px, _py - 1],
                    [_px, _py + 1]
                ];
                for (var _ni = 0; _ni < 4; _ni++) {
                    var _nx = _nbrs[_ni][0];
                    var _ny = _nbrs[_ni][1];
                    if (_nx < 0 || _nx >= 24 || _ny < 0 || _ny >= 21) {
                        continue;
                    }
                    if (_visited[_nx + _ny * 24]) {
                        continue;
                    }
                    var _nbit = _v2.bits[_bit_base + _ny * 24 + _nx];
                    if (_nbit == _old_bit) {
                        _visited[_nx + _ny * 24] = 1;
                        array_push(_stack, [_nx, _ny]);
                    }
                }
            }
        }
        _v2.fill_armed = false;
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