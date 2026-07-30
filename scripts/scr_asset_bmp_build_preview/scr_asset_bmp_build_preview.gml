function scr_asset_bmp_build_preview(_asset) {
	
	// check guard
    if (!buffer_exists(_asset.buffer)) exit;
    var _buf = _asset.buffer;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _min_size = _is_hires ? 9002 : 10003;
    if (buffer_get_size(_buf) < _min_size) exit;
    
    if (variable_struct_exists(_asset.meta, "preview_surf") &&
        surface_exists(_asset.meta.preview_surf)) {
        surface_free(_asset.meta.preview_surf);
    }
    if (!_is_hires) {
        _asset.meta.bg_col = buffer_peek(_buf, 10002, buffer_u8) & 0xF;
    } else if (!variable_struct_exists(_asset.meta, "bg_col")) {
        _asset.meta.bg_col = 0;
    }

    // ── COLLISION TAG GRID ──
    // 40x25 char cells, one byte each: 0 = none, 1..16 = collision type.
    // Same layout regardless of MC/HiRes — this rides on the 1000-entry
    // screen-RAM-sized grid, not on the pixel format.
    if (!variable_struct_exists(_asset.meta, "coll_types")) {
        _asset.meta.coll_types = array_create(1000, 0);
    }
    if (!is_array(_asset.meta.coll_types) || array_length(_asset.meta.coll_types) != 1000) {
        _asset.meta.coll_types = array_create(1000, 0);
    }

// Build a raw RGBA buffer and blast it directly — no draw_point clipping issues
    var _surf_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    
    // Pre-cache all 16 pepto colours as R,G,B components
    var _pr = array_create(16, 0);
    var _pg = array_create(16, 0);
    var _pb = array_create(16, 0);
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pr[_c] = color_get_red(_col);
        _pg[_c] = color_get_green(_col);
        _pb[_c] = color_get_blue(_col);
    }
    
    if (!_is_hires) {
        // ── MULTICOLOUR DECODE — 2 bits/pixel, 4 colours/cell, 160 MC px wide ──
        var _bg = _asset.meta.bg_col;
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _col_byte = buffer_peek(_buf, 9002 + _cell, buffer_u8) & 0xF;
                var _c1       = _scr >> 4;
                var _c2       = _scr & 0xF;
                for (var _bp = 0; _bp < 4; _bp++) {
                    var _val = (_bmp_byte >> (6 - _bp * 2)) & 0x3;
                    var _ci  = (_val == 0) ? _bg : ((_val == 1) ? _c1 : ((_val == 2) ? _c2 : _col_byte));
                    // Each MC pixel = 2 screen pixels wide in 320px space
                    var _screen_x = (_cx * 4 + _bp) * 2;
                    var _offset1  = (_py * 320 + _screen_x) * 4;
                    var _offset2  = (_py * 320 + _screen_x + 1) * 4;
                    buffer_poke(_surf_buf, _offset1,     buffer_u8, _pr[_ci]);
                    buffer_poke(_surf_buf, _offset1 + 1, buffer_u8, _pg[_ci]);
                    buffer_poke(_surf_buf, _offset1 + 2, buffer_u8, _pb[_ci]);
                    buffer_poke(_surf_buf, _offset1 + 3, buffer_u8, 255);
                    buffer_poke(_surf_buf, _offset2,     buffer_u8, _pr[_ci]);
                    buffer_poke(_surf_buf, _offset2 + 1, buffer_u8, _pg[_ci]);
                    buffer_poke(_surf_buf, _offset2 + 2, buffer_u8, _pb[_ci]);
                    buffer_poke(_surf_buf, _offset2 + 3, buffer_u8, 255);
                }
            }
        }
   } else {
        // ── HIRES DECODE — 1 bit/pixel, 2 colours/cell, full 320px wide ──
        // Screen RAM byte per cell: high nibble = FG (bit=1), low nibble = BG (bit=0).
        // The file already stores exactly the role model's data (per-cell fg/bg
        // colour + per-pixel bit), so seed hr_role_mask/hr_cell_fg_col/hr_cell_bg_col
        // straight from it here — this is what keeps a loaded/rebuilt HiRes asset's
        // colour-editing behaviour correct without a separate bootstrap pass.
        _asset.meta.hr_role_mask   = array_create(64000, 0);
        _asset.meta.hr_cell_fg_col = array_create(1000, 0);
        _asset.meta.hr_cell_bg_col = array_create(1000, 0);
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _fg       = _scr >> 4;
                var _bg_cell  = _scr & 0xF;
                _asset.meta.hr_cell_fg_col[_cell] = _fg;
                _asset.meta.hr_cell_bg_col[_cell] = _bg_cell;
                for (var _bp = 0; _bp < 8; _bp++) {
                    var _bit = (_bmp_byte >> (7 - _bp)) & 0x1;
                    var _ci  = _bit ? _fg : _bg_cell;
                    var _screen_x = _cx * 8 + _bp;
                    var _offset   = (_py * 320 + _screen_x) * 4;
                    buffer_poke(_surf_buf, _offset,     buffer_u8, _pr[_ci]);
                    buffer_poke(_surf_buf, _offset + 1, buffer_u8, _pg[_ci]);
                    buffer_poke(_surf_buf, _offset + 2, buffer_u8, _pb[_ci]);
                    buffer_poke(_surf_buf, _offset + 3, buffer_u8, 255);
                    _asset.meta.hr_role_mask[_py * 320 + _screen_x] = _bit;
                }
            }
        }
    }
    
_asset.meta.preview_surf = surface_create(320, 200);
    buffer_set_surface(_surf_buf, _asset.meta.preview_surf, 0);
    buffer_delete(_surf_buf);
    _asset.meta.has_data = true;
    
    // Reconstruct bg_mask.
    // MC: derive it from RGB match against the single global bg colour, as before.
    // HiRes: there's no single global bg to test against (every cell has its own),
    // so re-walk the same bit values decoded above instead.
    _asset.meta.bg_mask = array_create(64000, 0);
    if (!_is_hires) {
        var _bg_r = _pr[_asset.meta.bg_col];
        var _bg_g = _pg[_asset.meta.bg_col];
        var _bg_b = _pb[_asset.meta.bg_col];
        var _mask_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
        buffer_get_surface(_mask_buf, _asset.meta.preview_surf, 0);
        for (var _mi = 0; _mi < 320 * 200; _mi++) {
            var _mo = _mi * 4;
            var _mr = buffer_peek(_mask_buf, _mo,     buffer_u8);
            var _mg = buffer_peek(_mask_buf, _mo + 1, buffer_u8);
            var _mb = buffer_peek(_mask_buf, _mo + 2, buffer_u8);
            _asset.meta.bg_mask[_mi] = (_mr == _bg_r && _mg == _bg_g && _mb == _bg_b) ? 0 : 1;
        }
        buffer_delete(_mask_buf);
    } else {
        for (var _py2 = 0; _py2 < 200; _py2++) {
            var _char_row2  = _py2 div 8;
            var _pixel_row2 = _py2 mod 8;
            for (var _cx2 = 0; _cx2 < 40; _cx2++) {
                var _cell2     = _char_row2 * 40 + _cx2;
                var _bmp_byte2 = buffer_peek(_buf, 2 + _cell2 * 8 + _pixel_row2, buffer_u8);
                for (var _bp2 = 0; _bp2 < 8; _bp2++) {
                    var _bit2 = (_bmp_byte2 >> (7 - _bp2)) & 0x1;
                    _asset.meta.bg_mask[_py2 * 320 + (_cx2 * 8 + _bp2)] = _bit2;
                }
            }
        }
    }
    _asset.meta.needs_mask_init = false;
}