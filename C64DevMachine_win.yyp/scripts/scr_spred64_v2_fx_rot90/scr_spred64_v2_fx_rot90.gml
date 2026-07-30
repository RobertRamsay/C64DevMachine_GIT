/// @function scr_spred64_v2_fx_rot90(_slot)
/// @desc Rotates the active slot 90 degrees clockwise. Uses a source-of-
///       truth snapshot so multiple rotations don't accumulate distortion:
///       the SOT is captured on the first ROT90 click after a destructive
///       edit (paint/flip/clear/fill/import), and subsequent rotations
///       render from the SOT at the new angle. Click ROT90 four times
///       and the original is perfectly restored.
///
///       HR mode: clean per-bit rotation of the central 21x21 region,
///       cols 0-1 and 22-23 cleared.
///
///       MC mode: visual rotation of the 12x21 MC-cell grid, with the
///       21x12 result stretched vertically (each MC cell becomes 2 tall)
///       AND squashed horizontally (every 2 output MC cells merge to 1).
///       The squash picks the leftmost cell of each merged pair, which is
///       deterministic and reversible from the SOT. Pixels outside the
///       central area are cleared.
function scr_spred64_v2_fx_rot90(_slot) {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (_slot < 0 || _slot >= 64) exit;
        var _v2       = spred64_v2;
        var _bit_base = _slot * 504;
        var _is_mc    = (_v2.sprite_modes[_slot] == 1);

        // ----- SNAPSHOT THE SOT IF INVALID -----
        if (!_v2.rot_sot_valid[_slot]) {
            for (var _si = 0; _si < 504; _si++) {
                _v2.rot_sot[_bit_base + _si] = _v2.bits[_bit_base + _si];
            }
            _v2.rot_sot_valid[_slot] = true;
            _v2.rot_angle[_slot]     = 0;
        }

        // ----- INCREMENT ANGLE -----
        _v2.rot_angle[_slot] = (_v2.rot_angle[_slot] + 1) mod 4;
        var _angle = _v2.rot_angle[_slot];

        // ----- RENDER SOT AT NEW ANGLE INTO WORKING BITS -----
        // Clear working bits first
        for (var _ci = 0; _ci < 504; _ci++) {
            _v2.bits[_bit_base + _ci] = 0;
        }

        if (_angle == 0) {
            // Identity — straight copy from SOT
            for (var _ai = 0; _ai < 504; _ai++) {
                _v2.bits[_bit_base + _ai] = _v2.rot_sot[_bit_base + _ai];
            }
        } else if (_is_mc) {
            // ----- MC ROTATION: visual MC-cell space -----
            // Source visible grid: 12 wide (MC cells) x 21 tall.
            // Read each MC pair from SOT into a flat 12x21 cell array.
            // Each cell stores the 2-bit MC value (0=BG, 1=MC1, 2=UC, 3=MC2).
            var _src_cells = array_create(12 * 21, 0);
            for (var _sy = 0; _sy < 21; _sy++) {
                for (var _sx_cell = 0; _sx_cell < 12; _sx_cell++) {
                    var _sx_bit = _sx_cell * 2;
                    var _bA = _v2.rot_sot[_bit_base + _sy * 24 + _sx_bit];
                    var _bB = _v2.rot_sot[_bit_base + _sy * 24 + _sx_bit + 1];
                    // Pack pair into 0..3:
                    //   BG=00 -> 0, MC1=01 -> 1, UC=10 -> 2, MC2=11 -> 3
                    _src_cells[_sx_cell + _sy * 12] = (_bA << 1) | _bB;
                }
            }

            // Build rotated cell grid. For each rotation, derive the
            // intermediate dimensions (W,H of rotated content in cells)
            // and the mapping from output (ox, oy) back to source cell.
            //
            // After 90° clockwise of a 12x21 grid, we get 21x12. To fit
            // back into 12x21 MC cells, we stretch each rotated row to
            // 2 rows (the "stretch vertically" rule, giving 21x24), then
            // squash each output column-pair to 1 by picking the leftmost
            // column (the "squash to fit" rule, giving 12x24), then crop
            // bottom to 21. The 3 lost rows are at the bottom.
            //
            // The same approach is applied symmetrically for 270°.
            //
            // For 180°, the cell grid is still 12x21 — no resize needed,
            // just mirror both axes.

            if (_angle == 2) {
                // 180°: mirror both axes
                for (var _oy = 0; _oy < 21; _oy++) {
                    for (var _ox_cell = 0; _ox_cell < 12; _ox_cell++) {
                        var _src_ox = 11 - _ox_cell;
                        var _src_oy = 20 - _oy;
                        var _pair = _src_cells[_src_ox + _src_oy * 12];
                        var _ob_a = (_pair >> 1) & 1;
                        var _ob_b =  _pair       & 1;
                        var _ox_bit = _ox_cell * 2;
                        _v2.bits[_bit_base + _oy * 24 + _ox_bit]     = _ob_a;
                        _v2.bits[_bit_base + _oy * 24 + _ox_bit + 1] = _ob_b;
                    }
                }
            } else {
                // 90° or 270° — stretch-vertical, squash-horizontal
                // Rotated intermediate grid: 21 wide x 12 tall (in cells)
                // After stretching to 2 tall per cell: 21 wide x 24 tall
                // After cropping bottom rows: 21 wide x 21 tall
                // After horizontal squash 2:1 (pick leftmost of each pair): 12 wide x 21 tall
                //
                // Combined: for each output cell (ox, oy) in 12x21:
                //   intermediate_x = ox * 2        (leftmost of merged pair)
                //   intermediate_y = oy / 2        (which rotated row, since each row is doubled vertically; bottom 3 dropped by oy bound)
                //   source_x, source_y = rotated mapping based on angle
                for (var _oy = 0; _oy < 21; _oy++) {
                    for (var _ox_cell = 0; _ox_cell < 12; _ox_cell++) {
                        var _int_x = _ox_cell * 2;             // 0..22, in rotated 21-wide grid
                        var _int_y = _oy div 2;                // 0..10
                        // Bounds check (intermediate x must be within 21)
                        if (_int_x >= 21) {
                            continue;
                        }
                        // Inverse rotation: where in the source grid does (_int_x, _int_y) come from?
                        var _src_x_cell;
                        var _src_y;
                        if (_angle == 1) {
                            // 90° CW: rotated[x][y] = source[y][H_src-1 - x]
                            // Source is 12x21, so rotated 21x12: rotated[x_cell][y] (x_cell:0..20, y:0..11)
                            //   maps to source[y][11 - x_cell]
                            // Wait — let's keep this consistent: source cell grid is 12x21 (W_src=12, H_src=21).
                            // 90° CW: rotated (rx, ry) where rx:0..H_src-1=20, ry:0..W_src-1=11
                            //   sources from source (sx, sy) = (ry, H_src-1 - rx) = (ry, 20 - rx)
                            _src_x_cell = _int_y;          // ry -> sx
                            _src_y      = 20 - _int_x;     // 20 - rx -> sy
                        } else {
                            // 270° CW: rotated (rx, ry) sources from (W_src-1 - ry, rx) = (11 - ry, rx)
                            _src_x_cell = 11 - _int_y;
                            _src_y      = _int_x;
                        }
                        // Bounds check on source
                        if (_src_x_cell < 0 || _src_x_cell >= 12) {
                            continue;
                        }
                        if (_src_y < 0 || _src_y >= 21) {
                            continue;
                        }
                        var _pair = _src_cells[_src_x_cell + _src_y * 12];
                        var _ob_a = (_pair >> 1) & 1;
                        var _ob_b =  _pair       & 1;
                        var _ox_bit = _ox_cell * 2;
                        _v2.bits[_bit_base + _oy * 24 + _ox_bit]     = _ob_a;
                        _v2.bits[_bit_base + _oy * 24 + _ox_bit + 1] = _ob_b;
                    }
                }
            }
        } else {
            // ----- HR ROTATION: per-bit, central 21x21 region -----
            // Read central 21x21 from SOT
            var _src_hr = array_create(21 * 21, 0);
            for (var _ly = 0; _ly < 21; _ly++) {
                for (var _lx = 0; _lx < 21; _lx++) {
                    _src_hr[_ly * 21 + _lx] =
                        _v2.rot_sot[_bit_base + _ly * 24 + (_lx + 2)];
                }
            }
            // Write back into central region according to angle
            for (var _ny = 0; _ny < 21; _ny++) {
                for (var _nx = 0; _nx < 21; _nx++) {
                    var _sx = 0;
                    var _sy = 0;
                    if (_angle == 1) {
                        // 90° CW: new[x][y] = source[y][20 - x]
                        _sx = _ny;
                        _sy = 20 - _nx;
                    } else if (_angle == 2) {
                        // 180°: new[x][y] = source[20 - x][20 - y]
                        _sx = 20 - _nx;
                        _sy = 20 - _ny;
                    } else {
                        // 270° CW: new[x][y] = source[20 - y][x]
                        _sx = 20 - _ny;
                        _sy = _nx;
                    }
                    _v2.bits[_bit_base + _ny * 24 + (_nx + 2)] =
                        _src_hr[_sy * 21 + _sx];
                }
            }
        }

        _v2.dirty = true;
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