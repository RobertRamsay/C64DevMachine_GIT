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

    // Pre-cache all 16 pepto colours as PACKED little-endian RGBA words.
    // One buffer_u32 poke replaces four buffer_u8 pokes per pixel, which is
    // 64000 writes per bitmap instead of 256000. On a 60-frame REU animation
    // that is the difference between a load you wait through and one you do
    // not. _pr/_pg/_pb are kept because the HiRes role-mask seeding and any
    // external caller may still want the components.
    var _pr = array_create(16, 0);
    var _pg = array_create(16, 0);
    var _pb = array_create(16, 0);
    var _pu = array_create(16, 0);
    for (var _c = 0; _c < 16; _c++) {
        var _col = scr_c64_pepto_colour(_c);
        _pr[_c] = color_get_red(_col);
        _pg[_c] = color_get_green(_col);
        _pb[_c] = color_get_blue(_col);
        _pu[_c] = _pr[_c] | (_pg[_c] << 8) | (_pb[_c] << 16) | (255 << 24);
    }

    // bg_mask is built INLINE below rather than by reading the finished
    // surface back off the GPU. The old MC path uploaded the buffer, pulled
    // all 256KB back with buffer_get_surface(), then compared each pixel's
    // RGB against the background RGB — a full pipeline stall plus 192000
    // buffer_peek calls, purely to recover a fact the decoder already knew.
    // Pepto indices map 1:1 to distinct colours, so "_ci equals _bg" is
    // exactly the same test as "these three bytes match", with no readback.
    var _mask = array_create(64000, 0);

    if (!_is_hires) {
        // ── MULTICOLOUR DECODE — 2 bits/pixel, 4 colours/cell, 160 MC px wide ──
        var _bg = _asset.meta.bg_col;
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            var _row_base  = _py * 320;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _col_byte = buffer_peek(_buf, 9002 + _cell, buffer_u8) & 0xF;
                var _c1       = _scr >> 4;
                var _c2       = _scr & 0xF;
                for (var _bp = 0; _bp < 4; _bp++) {
                    var _val = (_bmp_byte >> (6 - _bp * 2)) & 0x3;
                    var _ci  = _bg;
                    if (_val == 1) {
                        _ci = _c1;
                    } else if (_val == 2) {
                        _ci = _c2;
                    } else if (_val == 3) {
                        _ci = _col_byte;
                    }
                    var _is_bg = 1;
                    if (_ci == _bg) {
                        _is_bg = 0;
                    }
                    // Each MC pixel = 2 screen pixels wide in 320px space
                    var _screen_x = (_cx * 4 + _bp) * 2;
                    var _pix      = _row_base + _screen_x;
                    var _word     = _pu[_ci];
                    buffer_poke(_surf_buf, _pix * 4,       buffer_u32, _word);
                    buffer_poke(_surf_buf, (_pix + 1) * 4, buffer_u32, _word);
                    _mask[_pix]     = _is_bg;
                    _mask[_pix + 1] = _is_bg;
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
        // bg_mask for HiRes is the raw bit value, which this same pass already
        // has in hand, so the old second 64000-pixel re-walk is gone too.
        var _role = array_create(64000, 0);
        var _fg_cols = array_create(1000, 0);
        var _bg_cols = array_create(1000, 0);
        for (var _py = 0; _py < 200; _py++) {
            var _char_row  = _py div 8;
            var _pixel_row = _py mod 8;
            var _row_base  = _py * 320;
            for (var _cx = 0; _cx < 40; _cx++) {
                var _cell     = _char_row * 40 + _cx;
                var _bmp_byte = buffer_peek(_buf, 2 + _cell * 8 + _pixel_row, buffer_u8);
                var _scr      = buffer_peek(_buf, 8002 + _cell, buffer_u8);
                var _fg       = _scr >> 4;
                var _bg_cell  = _scr & 0xF;
                _fg_cols[_cell] = _fg;
                _bg_cols[_cell] = _bg_cell;
                for (var _bp = 0; _bp < 8; _bp++) {
                    var _bit = (_bmp_byte >> (7 - _bp)) & 0x1;
                    var _ci  = _bg_cell;
                    if (_bit == 1) {
                        _ci = _fg;
                    }
                    var _pix = _row_base + _cx * 8 + _bp;
                    buffer_poke(_surf_buf, _pix * 4, buffer_u32, _pu[_ci]);
                    _role[_pix] = _bit;
                    _mask[_pix] = _bit;
                }
            }
        }
        _asset.meta.hr_role_mask   = _role;
        _asset.meta.hr_cell_fg_col = _fg_cols;
        _asset.meta.hr_cell_bg_col = _bg_cols;
    }
    
_asset.meta.preview_surf = surface_create(320, 200);
    buffer_set_surface(_surf_buf, _asset.meta.preview_surf, 0);
    buffer_delete(_surf_buf);
    _asset.meta.has_data = true;

    _asset.meta.bg_mask = _mask;
    _asset.meta.needs_mask_init = false;
}
