/// @function scr_asset_kla_save(_asset)
/// @desc Encodes the preview surface back into the KLA (MC, 10003-byte) or
///       HiRes (9002-byte) format and saves to disk.

function scr_asset_kla_save(_asset) {
    if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) return;

    var _is_hires = scr_asset_bmp_is_hires(_asset);

    // Only cleanup if there are actual clashes — don't scan clean canvases
    var _has_clashes = false;
    if (variable_struct_exists(_asset.meta, "clash_grid")) {
        var _cg = _asset.meta.clash_grid;
        for (var _ci = 0; _ci < 1000; _ci++) {
            if (_cg[_ci]) { _has_clashes = true; break; }
        }
    }
    if (_has_clashes) scr_asset_kla_process_surface(_asset, true, -1);

    var _bg = _asset.meta.bg_col;

    // TONE-SORTED quantisation. MC only — see scr_c64_tone_group.
    var _tone_sorted = false;
    if (variable_struct_exists(_asset.meta, "tone_sorted")) {
        _tone_sorted = _asset.meta.tone_sorted;
    }

    var _buf_size = _is_hires ? 9002 : 10003;
    var _buf = buffer_create(_buf_size, buffer_fixed, 1);

    // 2. Write Header (Load Address $6000 -> 0x00, 0x60)
    buffer_write(_buf, buffer_u8, 0x00);
    buffer_write(_buf, buffer_u8, 0x60);

    // 3. Fast color lookup hash
    var _color_hash = {};
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        var _sr = color_get_red(_col); var _sg = color_get_green(_col); var _sb = color_get_blue(_col);
        _color_hash[$ (_sr << 16) | (_sg << 8) | _sb] = _c;
    }

    var _surf_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_surf_buf, _asset.meta.preview_surf, 0);

    // Pre-allocate C64 memory blocks
    var _bmp_ram = array_create(8000, 0);
    var _scr_ram = array_create(1000, 0);
    var _col_ram = array_create(1000, 0); // unused in HiRes — no colour RAM channel there

    // 4. Encode the 40x25 Character Grid
    for (var _gy = 0; _gy < 25; _gy++) {
        for (var _gx = 0; _gx < 40; _gx++) {
            var _cell_idx = _gy * 40 + _gx;

            if (!_is_hires) {
                // ── MULTICOLOUR CELL ENCODE (unchanged) ──
                var _unique = [];
                var _counts = array_create(16, 0);
                var _cell_pixels = array_create(32, 0); // 32 MC pixels per cell

                // Extract all colors used in this 8x8 block
                for (var _py = 0; _py < 8; _py++) {
                    for (var _px = 0; _px < 8; _px += 2) {
                        var _abs_x = clamp((_gx * 8) + _px, 0, 319);
                        var _abs_y = clamp((_gy * 8) + _py, 0, 199);
                        var _offset = (_abs_y * 320 + _abs_x) * 4;

                        var _r = buffer_peek(_surf_buf, _offset, buffer_u8);
                        var _g = buffer_peek(_surf_buf, _offset + 1, buffer_u8);
                        var _b = buffer_peek(_surf_buf, _offset + 2, buffer_u8);

                        var _c64_idx = _color_hash[$ (_r << 16) | (_g << 8) | _b] ?? _bg;

                        _cell_pixels[_py * 4 + (_px div 2)] = _c64_idx;

                        // Tally non-BG colors to assign C1, C2, and C3 mapping
                        if (_c64_idx != _bg) {
                            if (_counts[_c64_idx] == 0) array_push(_unique, _c64_idx);
                            _counts[_c64_idx]++;
                        }
                    }
                }

                // Assign block palette. Sort by pixel count (most-used gets C1) so
                // the palette is deterministic for a given set of pixels regardless
                // of position; back-fill unused slots with C1 rather than 0, so an
                // unassigned bit-pair can never mean "black".
                var _sorted = [];
                for (var _ui = 0; _ui < array_length(_unique); _ui++) {
                    array_push(_sorted, _unique[_ui]);
                }
                for (var _si = 1; _si < array_length(_sorted); _si++) {
                    var _key = _sorted[_si];
                    var _sj  = _si - 1;
                    while (_sj >= 0) {
                        var _swap = false;
                        if (_counts[_sorted[_sj]] < _counts[_key]) {
                            _swap = true;
                        } else if (_counts[_sorted[_sj]] == _counts[_key] && _sorted[_sj] > _key) {
                            _swap = true;
                        }
                        if (!_swap) {
                            break;
                        }
                        _sorted[_sj + 1] = _sorted[_sj];
                        _sj -= 1;
                    }
                    _sorted[_sj + 1] = _key;
                }

                var _uniq_n = array_length(_sorted);
                var _c1 = 0;
                var _c2 = 0;
                var _c3 = 0;

                if (_tone_sorted) {
                    // ── TONE-SORTED ASSIGNMENT ────────────────────────────────
                    var _win_a = -1;
                    var _win_b = -1;
                    var _win_c = -1;
                    var _cnt_a = 0;
                    var _cnt_b = 0;
                    var _cnt_c = 0;

                    for (var _ti = 0; _ti < _uniq_n; _ti++) {
                        var _tc = _sorted[_ti];
                        var _tg = scr_c64_tone_group(_tc);
                        if (_tg == 1) {
                            if (_counts[_tc] > _cnt_a) {
                                _cnt_a = _counts[_tc];
                                _win_a = _tc;
                            }
                        } else if (_tg == 2) {
                            if (_counts[_tc] > _cnt_b) {
                                _cnt_b = _counts[_tc];
                                _win_b = _tc;
                            }
                        } else {
                            if (_counts[_tc] > _cnt_c) {
                                _cnt_c = _counts[_tc];
                                _win_c = _tc;
                            }
                        }
                    }

                    var _fallback = 0;
                    if (_win_b >= 0) {
                        _fallback = _win_b;
                    } else if (_win_a >= 0) {
                        _fallback = _win_a;
                    } else if (_win_c >= 0) {
                        _fallback = _win_c;
                    }

                    if (_win_a >= 0) {
                        _c1 = _win_a;
                    } else {
                        _c1 = _fallback;
                    }
                    if (_win_b >= 0) {
                        _c2 = _win_b;
                    } else {
                        _c2 = _fallback;
                    }
                    if (_win_c >= 0) {
                        _c3 = _win_c;
                    } else {
                        _c3 = _fallback;
                    }
                } else {
                    // ── COUNT-SORTED ASSIGNMENT (default) ─────────────────────
                    if (_uniq_n > 0) {
                        _c1 = _sorted[0];
                        _c2 = _c1;
                        _c3 = _c1;
                    }
                    if (_uniq_n > 1) {
                        _c2 = _sorted[1];
                        _c3 = _sorted[1];
                    }
                    if (_uniq_n > 2) {
                        _c3 = _sorted[2];
                    }
                }

                // Pack Screen RAM (Upper Nibble = C1, Lower Nibble = C2) and Color RAM (C3)
                _scr_ram[_cell_idx] = (_c1 << 4) | _c2;
                _col_ram[_cell_idx] = _c3;

                // Pack Bitmap Data
                for (var _py = 0; _py < 8; _py++) {
                    var _bmp_byte = 0;
                    for (var _mpx = 0; _mpx < 4; _mpx++) {
                        var _col2 = _cell_pixels[_py * 4 + _mpx];
                        var _bit = 0; // Default 00 (BG)
                        if (_col2 == _c1) _bit = 1;      // 01
                        else if (_col2 == _c2) _bit = 2; // 10
                        else if (_col2 == _c3) _bit = 3; // 11

                        _bmp_byte = _bmp_byte | (_bit << (6 - (_mpx * 2)));
                    }
                    _bmp_ram[_cell_idx * 8 + _py] = _bmp_byte;
                }

            } else {
                // ── HIRES CELL ENCODE ──
                // Only 2 colours/cell: the dominant colour becomes BG, the
                // runner-up becomes FG. Screen RAM byte: high nibble = FG
                // (bit=1), low nibble = BG (bit=0). No colour RAM channel.
                var _unique = [];
                var _counts = array_create(16, 0);
                var _cell_pixels = array_create(64, 0); // 64 single pixels per cell

                for (var _py = 0; _py < 8; _py++) {
                    for (var _px = 0; _px < 8; _px++) {
                        var _abs_x = clamp((_gx * 8) + _px, 0, 319);
                        var _abs_y = clamp((_gy * 8) + _py, 0, 199);
                        var _offset = (_abs_y * 320 + _abs_x) * 4;

                        var _r = buffer_peek(_surf_buf, _offset, buffer_u8);
                        var _g = buffer_peek(_surf_buf, _offset + 1, buffer_u8);
                        var _b = buffer_peek(_surf_buf, _offset + 2, buffer_u8);

                        var _c64_idx = _color_hash[$ (_r << 16) | (_g << 8) | _b] ?? _bg;

                        _cell_pixels[_py * 8 + _px] = _c64_idx;

                        if (_counts[_c64_idx] == 0) array_push(_unique, _c64_idx);
                        _counts[_c64_idx]++;
                    }
                }

                var _sorted = [];
                for (var _ui = 0; _ui < array_length(_unique); _ui++) {
                    array_push(_sorted, _unique[_ui]);
                }
                for (var _si = 1; _si < array_length(_sorted); _si++) {
                    var _key = _sorted[_si];
                    var _sj  = _si - 1;
                    while (_sj >= 0) {
                        var _swap = false;
                        if (_counts[_sorted[_sj]] < _counts[_key]) {
                            _swap = true;
                        } else if (_counts[_sorted[_sj]] == _counts[_key] && _sorted[_sj] > _key) {
                            _swap = true;
                        }
                        if (!_swap) {
                            break;
                        }
                        _sorted[_sj + 1] = _sorted[_sj];
                        _sj -= 1;
                    }
                    _sorted[_sj + 1] = _key;
                }

                var _uniq_n2 = array_length(_sorted);
                var _c_bg = _bg;
                var _c_fg = _bg;
                if (_uniq_n2 > 0) {
                    _c_bg = _sorted[0];
                    _c_fg = _c_bg;
                }
                if (_uniq_n2 > 1) {
                    _c_fg = _sorted[1];
                }

                _scr_ram[_cell_idx] = (_c_fg << 4) | _c_bg;

                for (var _py = 0; _py < 8; _py++) {
                    var _bmp_byte = 0;
                    for (var _px = 0; _px < 8; _px++) {
                        var _pc = _cell_pixels[_py * 8 + _px];
                        // Single-colour cells stay all-BG bits — fg==bg there
                        // anyway, so the pixel renders identically either way.
                        if (_uniq_n2 > 1 && _pc == _c_fg) {
                            _bmp_byte = _bmp_byte | (0x80 >> _px);
                        }
                    }
                    _bmp_ram[_cell_idx * 8 + _py] = _bmp_byte;
                }
            }
        }
    }

    // 5. Blast data into final byte buffer
    for (var _i = 0; _i < 8000; _i++) buffer_write(_buf, buffer_u8, _bmp_ram[_i]);
    for (var _i = 0; _i < 1000; _i++) buffer_write(_buf, buffer_u8, _scr_ram[_i]);
    if (!_is_hires) {
        for (var _i = 0; _i < 1000; _i++) buffer_write(_buf, buffer_u8, _col_ram[_i]);
        buffer_write(_buf, buffer_u8, _bg); // Final Byte = BG Color (MC only)
    }

    buffer_delete(_surf_buf);

    // 6. Ensure directory exists and write to disk
    var _dir = filename_dir(_asset.file);
    if (!directory_exists(_dir)) directory_create(_dir);
    buffer_save(_buf, _asset.file);

// Update global memory so the rest of the application recognizes the new data instantly
    if (variable_struct_exists(_asset, "buffer") && buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
_asset.buffer = _buf;
    // Explicitly flag that this asset now contains valid C64 data
    _asset.meta.has_data = true;
    _asset.meta.needs_mask_init = false;


    // Broadcast the update...
    with (all) {
        if (variable_instance_exists(id, "instructions")) {
            if (is_array(instructions) && array_length(instructions) > 0 && is_array(instructions[0])) {
                // If the Node's label matches the asset name, force the update!
                if (string(instructions[0][1]) == _asset.name) {
                    
                    // Cleanup old buffer if it exists
                    if (variable_instance_exists(id, "kla_buffer") && kla_buffer != -1 && buffer_exists(kla_buffer)) {
                        buffer_delete(kla_buffer);
                    }
                    
                    // Inject file data and FORCE the filename string update
                    kla_buffer = buffer_load(_asset.file);
                    kla_filename = filename_name(_asset.file);
                    
                    // Update the instruction parameter so the workspace knows the file link is real
                    if (array_length(instructions[0]) > 2) {
                        // Assuming instructions[0][2] or similar holds your file/address logic
                        // Ensure the Node knows it now has a valid file path
                    }
                    
                    // Destroy the Node's thumbnail surface so it is forced to redraw the new pixels
                    if (variable_instance_exists(id, "preview_surf")) {
                        if (surface_exists(preview_surf)) surface_free(preview_surf); 
                    }
                    preview_surf = -1; // Nullify so the Node knows it's truly gone
                    
                    // Force the workspace to repaint immediately
                    if (variable_global_exists("undo_dirty")) {
                        global.undo_dirty = true;
                    }
                }
            }
        }
    }
}