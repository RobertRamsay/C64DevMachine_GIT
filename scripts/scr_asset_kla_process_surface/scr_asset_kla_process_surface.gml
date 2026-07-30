/// @function scr_asset_kla_process_surface(_asset, _do_cleanup, _old_bg)
/// @desc Extremely fast buffer-based surface processor for scanning clashes, swapping BG colors, and cleanup.
///       Branches on bmp_mode: MC allows 3 colours + shared global bg per cell;
///       HiRes allows exactly 2 colours total per cell, both cell-local.

function scr_asset_kla_process_surface(_asset, _do_cleanup, _old_bg) {
    if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) return;
    if (!variable_struct_exists(_asset.meta, "clash_grid")) _asset.meta.clash_grid = array_create(1000, false);
    if (!variable_struct_exists(_asset.meta, "bg_mask")) _asset.meta.bg_mask = array_create(64000, 0); 
    
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _surf = _asset.meta.preview_surf;
    var _bg = _asset.meta.bg_col;
    
    // 1. Build an Ultra-Fast Color Lookup Hash
    var _color_hash = {};
    var _pepto_r = array_create(16), _pepto_g = array_create(16), _pepto_b = array_create(16);
    
	for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pepto_r[_c] = color_get_red(_col);
        _pepto_g[_c] = color_get_green(_col);
        _pepto_b[_c] = color_get_blue(_col);
        
        // Use an integer key for speed: (R << 16 | G << 8 | B)
        var _key = (_pepto_r[_c] << 16) | (_pepto_g[_c] << 8) | _pepto_b[_c];
        _color_hash[$ _key] = _c;
    }
    
    var _match_color = function(_r, _g, _b, _pr, _pg, _pb) {
        var _best = 0; var _min_dist = 999999;
        for (var _i = 0; _i < 16; _i++) {
            var _dist = abs(_r - _pr[_i]) + abs(_g - _pg[_i]) + abs(_b - _pb[_i]);
            if (_dist < _min_dist) { _min_dist = _dist; _best = _i; }
        }
        return _best;
    };
    
    // Extract Surface to Memory Buffer
    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    var _surface_changed = false;

    // 2. BG COLOR SWAP PASS — MC only. HiRes no longer has an editable
    // background concept at all: untouched canvas is always fixed black, and
    // every touched cell resolves its own pair per-cell (see the HiRes branch
    // below), so there's no "old bg -> new bg" sweep that applies to it.
    if (!_is_hires && _old_bg != undefined && _old_bg >= 0 && _old_bg <= 15 && _old_bg != _bg) {
var _new_r = _pepto_r[_bg], _new_g = _pepto_g[_bg], _new_b = _pepto_b[_bg];
    var _old_r = _pepto_r[_old_bg], _old_g = _pepto_g[_old_bg], _old_b = _pepto_b[_old_bg];

        for (var _i = 0; _i < 320 * 200 * 4; _i += 4) {
            // ONLY sweep if mask is unprotected AND pixel is actually the old bg colour
            if (_asset.meta.bg_mask[_i / 4] == 0) {
                var _pr = buffer_peek(_buf, _i,     buffer_u8);
                var _pg = buffer_peek(_buf, _i + 1, buffer_u8);
                var _pb = buffer_peek(_buf, _i + 2, buffer_u8);
                if (_pr != _old_r || _pg != _old_g || _pb != _old_b) continue;
                buffer_poke(_buf, _i, buffer_u8, _new_r);
                buffer_poke(_buf, _i + 1, buffer_u8, _new_g);
                buffer_poke(_buf, _i + 2, buffer_u8, _new_b);
                _surface_changed = true;
            }
        }
    }

	// 3. SCAN AND CLEANUP PASS
	var _color_counts = array_create(16, 0);
    var _top_cols = array_create(3, -1);
	
    for (var _gy = 0; _gy < 25; _gy++) {
        for (var _gx = 0; _gx < 40; _gx++) {
            var _grid_idx = _gy * 40 + _gx;
            for (var _cc = 0; _cc < 16; _cc++) _color_counts[_cc] = 0;
            var _unique_colors = 0;
            
            if (!_is_hires) {
                // ── MULTICOLOUR SCAN + CLEANUP (unchanged) ──
                // Read 4x8 MC block (8x8 pixels on 320x200 surface)
                for (var _py = 0; _py < 8; _py++) {
                    for (var _px = 0; _px < 8; _px += 2) {
                        // Force absolute integer anchoring
                        var _abs_x = clamp((_gx * 8) + _px, 0, 319);
                        var _abs_y = clamp((_gy * 8) + _py, 0, 199);
                        var _offset = (_abs_y * 320 + _abs_x) * 4;
                        var _r = buffer_peek(_buf, _offset, buffer_u8);
                        var _g = buffer_peek(_buf, _offset + 1, buffer_u8);
                        var _b = buffer_peek(_buf, _offset + 2, buffer_u8);
                        
                        var _rgb_key = (_r << 16) | (_g << 8) | _b;
                        var _c64_idx = _color_hash[$ _rgb_key];

                        // HEAL PASS: snap off-palette (e.g. Aseprite) RGB to the nearest Pepto colour.
                        if (_c64_idx == undefined) {
                            _c64_idx = _match_color(_r, _g, _b, _pepto_r, _pepto_g, _pepto_b);
                            buffer_poke(_buf, _offset,     buffer_u8, _pepto_r[_c64_idx]);
                            buffer_poke(_buf, _offset + 1, buffer_u8, _pepto_g[_c64_idx]);
                            buffer_poke(_buf, _offset + 2, buffer_u8, _pepto_b[_c64_idx]);
                            buffer_poke(_buf, _offset + 3, buffer_u8, 255);
                            _surface_changed = true;
                        }
                        else {
                            if (_r != _pepto_r[_c64_idx] || _g != _pepto_g[_c64_idx] || _b != _pepto_b[_c64_idx]) {
                                buffer_poke(_buf, _offset,     buffer_u8, _pepto_r[_c64_idx]);
                                buffer_poke(_buf, _offset + 1, buffer_u8, _pepto_g[_c64_idx]);
                                buffer_poke(_buf, _offset + 2, buffer_u8, _pepto_b[_c64_idx]);
                                buffer_poke(_buf, _offset + 3, buffer_u8, 255);
                                _surface_changed = true;
                            }
                        }
                        
                        if (_c64_idx != _bg) {
                            if (_color_counts[_c64_idx] == 0) _unique_colors++;
                            _color_counts[_c64_idx]++;
                        }
                    }
                }
                
                // C64 Rule: 3 Colors (C1, C2, C3) + 1 Background Color = Legal.
                _asset.meta.clash_grid[_grid_idx] = (_unique_colors > 3);
                
                // Execute Cleanup 
                if (_do_cleanup && _unique_colors > 3) {
                    _surface_changed = true;
                    _asset.meta.clash_grid[_grid_idx] = false;
                    
                    _top_cols[0] = -1; _top_cols[1] = -1; _top_cols[2] = -1;
                    for (var _t = 0; _t < 3; _t++) {
                        var _highest_cnt = 0, _best_col = -1;
                        for (var _c = 0; _c < 16; _c++) {
                            if (_color_counts[_c] > _highest_cnt) {
                                _highest_cnt = _color_counts[_c];
                                _best_col = _c;
                            }
                        }
                        if (_best_col != -1) {
                            _top_cols[_t] = _best_col;
                            _color_counts[_best_col] = -1; 
                        }
                    }
                    
                    for (var _py = 0; _py < 8; _py++) {
                        for (var _px = 0; _px < 8; _px += 2) {
                            var _abs_x = clamp((_gx * 8) + _px, 0, 319);
                            var _abs_y = clamp((_gy * 8) + _py, 0, 199);
                            
                            var _offset = (_abs_y * 320 + _abs_x) * 4;
                            var _r = buffer_peek(_buf, _offset, buffer_u8);
                            var _g = buffer_peek(_buf, _offset + 1, buffer_u8);
                            var _b = buffer_peek(_buf, _offset + 2, buffer_u8);
                            
                            var _rgb_key = (_r << 16) | (_g << 8) | _b;
                            var _c64_idx = _color_hash[$ _rgb_key] ?? _match_color(_r, _g, _b, _pepto_r, _pepto_g, _pepto_b);
                            
                            // Force guilty pixels to the CLOSEST ALLOWED color in this block
                            if (_c64_idx != _bg && _c64_idx != _top_cols[0] && _c64_idx != _top_cols[1] && _c64_idx != _top_cols[2]) {
                                
                                // Find closest allowed color using RGB Manhattan distance
                                var _best_col = _bg;
                                var _min_dist = 999999;
                                var _allowed_cols = [_bg,
                                    (_top_cols[0] != -1) ? _top_cols[0] : _bg,
                                    (_top_cols[1] != -1) ? _top_cols[1] : _bg,
                                    (_top_cols[2] != -1) ? _top_cols[2] : _bg];
                                for (var _ai = 0; _ai < 4; _ai++) {
                                    var _ac = _allowed_cols[_ai];
                                    var _dist = abs(_r - _pepto_r[_ac]) + abs(_g - _pepto_g[_ac]) + abs(_b - _pepto_b[_ac]);
                                    if (_dist < _min_dist) {
                                        _min_dist = _dist;
                                        _best_col = _ac;
                                    }
                                }

                                // Apply the closest color
                                var _rep_r = _pepto_r[_best_col];
                                var _rep_g = _pepto_g[_best_col];
                                var _rep_b = _pepto_b[_best_col];

                                buffer_poke(_buf, _offset, buffer_u8, _rep_r);
                                buffer_poke(_buf, _offset + 1, buffer_u8, _rep_g);
                                buffer_poke(_buf, _offset + 2, buffer_u8, _rep_b);
                                
                                var _new_mask = (_best_col == _bg) ? 0 : 1;
                                _asset.meta.bg_mask[_offset / 4] = _new_mask; 
                                
                                var _offset2 = (_abs_y * 320 + _abs_x + 1) * 4;
                                buffer_poke(_buf, _offset2, buffer_u8, _rep_r);
                                buffer_poke(_buf, _offset2 + 1, buffer_u8, _rep_g);
                                buffer_poke(_buf, _offset2 + 2, buffer_u8, _rep_b);
                                _asset.meta.bg_mask[_offset2 / 4] = _new_mask; 
                            }
                        }
                    }
                }
                
          } else {
                // ── HIRES: reseed ONLY cells the paint tools never touched ──
                // The draw tools already repaint each cell's full role
                // IMMEDIATELY at paint time and keep hr_cell_fg_col/
                // hr_cell_bg_col/hr_role_mask authoritative — this pass must
                // NEVER re-derive a pair from raw pixel counts for a cell
                // those tools already track, or a stroke that crosses 50%
                // coverage gets re-crowned as "dominant" and overwrites
                // whatever was actually assigned (that was this exact bug:
                // right-click set bg, then painting fg past 50% silently
                // flipped the whole cell to fg-only).
                //
                // So: first check whether the buffer ALREADY matches what
                // the existing role model predicts. If it does, this cell is
                // already correctly tracked — leave it alone completely, no
                // rescan, no rewrite. Only cells that DON'T match (PNG import
                // wrote raw RGBA directly and never touched the role arrays,
                // so they're still sitting at the all-zero default) fall
                // through to the count-based derive/reseed fallback below.
                if (!variable_struct_exists(_asset.meta, "hr_role_mask"))   _asset.meta.hr_role_mask   = array_create(64000, 0);
                if (!variable_struct_exists(_asset.meta, "hr_cell_fg_col")) _asset.meta.hr_cell_fg_col = array_create(1000, 0);
                if (!variable_struct_exists(_asset.meta, "hr_cell_bg_col")) _asset.meta.hr_cell_bg_col = array_create(1000, 0);
                
                var _existing_fg = _asset.meta.hr_cell_fg_col[_grid_idx];
                var _existing_bg = _asset.meta.hr_cell_bg_col[_grid_idx];
                var _all_match = true;
                for (var _pyc = 0; _pyc < 8 && _all_match; _pyc++) {
                    for (var _pxc = 0; _pxc < 8 && _all_match; _pxc++) {
                        var _abs_xc = clamp((_gx * 8) + _pxc, 0, 319);
                        var _abs_yc = clamp((_gy * 8) + _pyc, 0, 199);
                        var _offc = (_abs_yc * 320 + _abs_xc) * 4;
                        var _rc = buffer_peek(_buf, _offc, buffer_u8);
                        var _gc = buffer_peek(_buf, _offc + 1, buffer_u8);
                        var _bc = buffer_peek(_buf, _offc + 2, buffer_u8);
                        var _predicted = (_asset.meta.hr_role_mask[_abs_yc * 320 + _abs_xc] == 1) ? _existing_fg : _existing_bg;
                        if (_rc != _pepto_r[_predicted] || _gc != _pepto_g[_predicted] || _bc != _pepto_b[_predicted]) {
                            _all_match = false;
                        }
                    }
                }
                
                if (_all_match) {
                    // Already correctly tracked by the paint tools — untouched.
                    _asset.meta.clash_grid[_grid_idx] = false;
                } else {
                    // Mismatch found — this cell bypassed the paint tools (e.g.
                    // PNG import wrote raw RGBA directly). Derive its pair from
                    // whatever's actually in the buffer and seed the role model.
                    var _hr_counts = array_create(16, 0);
                    var _hr_unique = 0;
                    for (var _py = 0; _py < 8; _py++) {
                        for (var _px = 0; _px < 8; _px++) {
                            var _abs_x = clamp((_gx * 8) + _px, 0, 319);
                            var _abs_y = clamp((_gy * 8) + _py, 0, 199);
                            var _offset = (_abs_y * 320 + _abs_x) * 4;
                            var _r = buffer_peek(_buf, _offset, buffer_u8);
                            var _g = buffer_peek(_buf, _offset + 1, buffer_u8);
                            var _b = buffer_peek(_buf, _offset + 2, buffer_u8);
                            var _rgb_key = (_r << 16) | (_g << 8) | _b;
                            var _c64_idx = _color_hash[$ _rgb_key];
                            if (_c64_idx == undefined) {
                                _c64_idx = _match_color(_r, _g, _b, _pepto_r, _pepto_g, _pepto_b);
                                buffer_poke(_buf, _offset,     buffer_u8, _pepto_r[_c64_idx]);
                                buffer_poke(_buf, _offset + 1, buffer_u8, _pepto_g[_c64_idx]);
                                buffer_poke(_buf, _offset + 2, buffer_u8, _pepto_b[_c64_idx]);
                                buffer_poke(_buf, _offset + 3, buffer_u8, 255);
                                _surface_changed = true;
                            }
                            if (_hr_counts[_c64_idx] == 0) _hr_unique++;
                            _hr_counts[_c64_idx]++;
                        }
                    }
                    
                    _asset.meta.clash_grid[_grid_idx] = (_hr_unique > 2);
                    
                    // Dominant -> bg role, runner-up -> fg role (matches
                    // scr_kla_encode_surface's convention so a resave produces
                    // the same bytes this pass just derived).
                    var _hr_counts_copy = array_create(16, 0);
                    array_copy(_hr_counts_copy, 0, _hr_counts, 0, 16);
                    var _hr_bg_win = -1, _hr_fg_win = -1;
                    for (var _t = 0; _t < 2; _t++) {
                        var _highest_cnt = 0, _best_col = -1;
                        for (var _c = 0; _c < 16; _c++) {
                            if (_hr_counts_copy[_c] > _highest_cnt) {
                                _highest_cnt = _hr_counts_copy[_c];
                                _best_col = _c;
                            }
                        }
                        if (_best_col != -1) {
                            if (_t == 0) { _hr_bg_win = _best_col; } else { _hr_fg_win = _best_col; }
                            _hr_counts_copy[_best_col] = -1;
                        }
                    }
                    if (_hr_bg_win == -1) _hr_bg_win = 0;
                    if (_hr_fg_win == -1) _hr_fg_win = _hr_bg_win;
                    
                    _asset.meta.hr_cell_bg_col[_grid_idx] = _hr_bg_win;
                    _asset.meta.hr_cell_fg_col[_grid_idx] = _hr_fg_win;
                    
                    for (var _py3 = 0; _py3 < 8; _py3++) {
                        for (var _px3 = 0; _px3 < 8; _px3++) {
                            var _abs_x3 = clamp((_gx * 8) + _px3, 0, 319);
                            var _abs_y3 = clamp((_gy * 8) + _py3, 0, 199);
                            var _offset3 = (_abs_y3 * 320 + _abs_x3) * 4;
                            var _r3 = buffer_peek(_buf, _offset3, buffer_u8);
                            var _g3 = buffer_peek(_buf, _offset3 + 1, buffer_u8);
                            var _b3 = buffer_peek(_buf, _offset3 + 2, buffer_u8);
                            var _idx3 = _color_hash[$ (_r3 << 16) | (_g3 << 8) | _b3] ?? _match_color(_r3, _g3, _b3, _pepto_r, _pepto_g, _pepto_b);
                            
                            var _use_fg = (_idx3 == _hr_fg_win && _hr_fg_win != _hr_bg_win);
                            _asset.meta.hr_role_mask[_abs_y3 * 320 + _abs_x3] = _use_fg ? 1 : 0;
                            
                            // Snap any 3rd+ colour overflow to the nearer of the two winners.
                            if (_idx3 != _hr_bg_win && _idx3 != _hr_fg_win) {
                                var _dist_bg = abs(_r3 - _pepto_r[_hr_bg_win]) + abs(_g3 - _pepto_g[_hr_bg_win]) + abs(_b3 - _pepto_b[_hr_bg_win]);
                                var _dist_fg = abs(_r3 - _pepto_r[_hr_fg_win]) + abs(_g3 - _pepto_g[_hr_fg_win]) + abs(_b3 - _pepto_b[_hr_fg_win]);
                                var _snap_col3 = (_dist_fg < _dist_bg) ? _hr_fg_win : _hr_bg_win;
                                buffer_poke(_buf, _offset3,     buffer_u8, _pepto_r[_snap_col3]);
                                buffer_poke(_buf, _offset3 + 1, buffer_u8, _pepto_g[_snap_col3]);
                                buffer_poke(_buf, _offset3 + 2, buffer_u8, _pepto_b[_snap_col3]);
                                _asset.meta.hr_role_mask[_abs_y3 * 320 + _abs_x3] = (_snap_col3 == _hr_fg_win && _hr_fg_win != _hr_bg_win) ? 1 : 0;
                                _surface_changed = true;
                            }
                        }
                    }
                }
            }
        }
    }
    
// Post-cleanup mask rebuild — MC only. HiRes mask is refreshed cell-by-cell
// above on every call (no separate global-bg pass makes sense for it).
    if (!_is_hires && variable_struct_exists(_asset.meta, "needs_mask_init") && _asset.meta.needs_mask_init) {
        var _bg_r2 = _pepto_r[_bg], _bg_g2 = _pepto_g[_bg], _bg_b2 = _pepto_b[_bg];
        // Re-read from buf (may have been modified by cleanup above)
        for (var _mi = 0; _mi < 320 * 200 * 4; _mi += 4) {
            var _mr = buffer_peek(_buf, _mi,     buffer_u8);
            var _mg = buffer_peek(_buf, _mi + 1, buffer_u8);
            var _mb = buffer_peek(_buf, _mi + 2, buffer_u8);
            _asset.meta.bg_mask[_mi / 4] = (_mr == _bg_r2 && _mg == _bg_g2 && _mb == _bg_b2) ? 0 : 1;
        }
        _asset.meta.needs_mask_init = false;
    } else if (_is_hires && variable_struct_exists(_asset.meta, "needs_mask_init")) {
        _asset.meta.needs_mask_init = false;
    }

    // Blast modified memory array back into the surface
    if (_surface_changed) {
        buffer_set_surface(_buf, _surf, 0);
    }
    
    buffer_delete(_buf);
}