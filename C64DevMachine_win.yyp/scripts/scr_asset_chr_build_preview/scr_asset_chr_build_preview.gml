/// scr_asset_chr_build_preview(_asset)
function scr_asset_chr_build_preview(_asset, _pixel_gap = 1) {
    if (!variable_struct_exists(_asset, "buffer") || !buffer_exists(_asset.buffer)) exit;
    if (!variable_struct_exists(_asset, "meta")) exit;

    var _total_chars = variable_struct_exists(_asset.meta, "char_count")
                     ? _asset.meta.char_count
                     : (buffer_get_size(_asset.buffer) div 8);

    if (_total_chars <= 0) exit;
    var _cols   = 16; // always 16-wide grid so partial last row renders correctly
    var _rows   = ceil(_total_chars / _cols);
    _asset.meta.cols = _cols;
    _asset.meta.rows = _rows;   // ACTUAL DATA row count — [+] ADD ROW / [-] REM
                                // ROW read/write this. Must not be resized off
                                // the ECM display grid below.
    var _scale  = 4;
    var _cell   = 8 * _scale;

    var _mc_fg_idx = variable_struct_exists(_asset.meta, "mc_fg") ? _asset.meta.mc_fg : 1;
    var _fg  = scr_c64_pepto_colour(_mc_fg_idx);
    var _bg  = scr_c64_pepto_colour(variable_struct_exists(_asset.meta, "mc_bg") ? _asset.meta.mc_bg : 0);
    var _grd = make_color_rgb(40, 40, 60);

    // ECM: always render the full 256-slot virtual grid (4 bands x 64 real
    // chars), regardless of how many real chars actually exist — so the grid
    // never needs resizing as the charset grows, and every band is visible
    // from the start. Real chars beyond what's actually defined just render
    // as blank band-tinted cells (bounds check further down). This is DISPLAY
    // ONLY: _asset.meta.rows/cols above stay tied to the real data.
    var _ecm_prev_mode    = variable_struct_exists(_asset.meta, "mc_mode") && (_asset.meta.mc_mode == 2);
    // ECM hardware caps at 64 real chars (6-bit char code) — bands scale to
    // however many real rows exist UP TO 4 rows (64 chars), never more. Any
    // buffer bytes past char 63 are unreachable on real hardware and are not
    // shown in the ECM preview at all — e.g. 16 real chars = 1 real row, so
    // ECM shows 4 rows total (one per band); 256 real chars still only shows
    // 4 real rows x 4 bands = 16 rows (chars 64-255 are dead data in ECM).
    var _ecm_real_rows = min(_rows, 4);
    var _disp_rows = _ecm_prev_mode ? (_ecm_real_rows * 4) : _rows;
    var _surf_w = _cols * _cell;
    var _surf_h = _disp_rows * _cell;
    var _ecm_prev_bgs  = [
        _bg,
        scr_c64_pepto_colour(variable_struct_exists(_asset.meta, "ecm_bg1") ? _asset.meta.ecm_bg1 : 6),
        scr_c64_pepto_colour(variable_struct_exists(_asset.meta, "ecm_bg2") ? _asset.meta.ecm_bg2 : 14),
        scr_c64_pepto_colour(variable_struct_exists(_asset.meta, "ecm_bg3") ? _asset.meta.ecm_bg3 : 3)
    ];

    // -------------------------------------------------------
    // SURFACE 1: preview_surf (pixel gap, for charset viewer)
    // -------------------------------------------------------
    if (variable_struct_exists(_asset.meta, "preview_surf") &&
        surface_exists(_asset.meta.preview_surf)) {
        surface_free(_asset.meta.preview_surf);
    }
    if (_surf_w <= 0 || _surf_h <= 0) exit;
    var _surf = surface_create(_surf_w, _surf_h);
    surface_set_target(_surf);
    draw_clear(_bg);
    for (var _dr = 0; _dr < _disp_rows; _dr++) {
        var _band     = _ecm_prev_mode ? (_dr div _ecm_real_rows) : 0;
        var _real_row = _ecm_prev_mode ? (_dr mod _ecm_real_rows) : _dr;
        for (var _dc = 0; _dc < _cols; _dc++) {
            var _src_char = (_real_row * _cols) + _dc;
            var _cx = _dc * _cell;
            var _cy = _dr * _cell;
            if (_ecm_prev_mode) {
                draw_set_color(_ecm_prev_bgs[_band]);
                draw_rectangle(_cx, _cy, _cx + _cell, _cy + _cell, false);
            }
            if (_src_char >= _total_chars) continue;
            var _src_base = _src_char * 8;
            if (_src_base + 8 > buffer_get_size(_asset.buffer)) continue;
            for (var _row = 0; _row < 8; _row++) {
                buffer_seek(_asset.buffer, buffer_seek_start, _src_base + _row);
                var _byte = buffer_read(_asset.buffer, buffer_u8);
                for (var _bit = 0; _bit < 8; _bit++) {
                    if (_byte & (0x80 >> _bit)) {
                        draw_set_color(_fg);
                        var _px = _cx + (_bit * _scale);
                        var _py = _cy + (_row * _scale);
                        draw_rectangle(_px, _py, _px + _scale - _pixel_gap, _py + _scale - _pixel_gap, false);
                    }
                }
            }
        }
    }
    draw_set_color(_grd);
    for (var _gc = 0; _gc <= _cols; _gc++)
        draw_line(_gc * _cell, 0, _gc * _cell, _surf_h);
    for (var _gr = 0; _gr <= _disp_rows; _gr++)
        draw_line(0, _gr * _cell, _surf_w, _gr * _cell);
    surface_reset_target();
    _asset.meta.preview_surf = _surf;
	

	

    // -------------------------------------------------------
    // SURFACE 2: preview_surf_clean (no pixel gap, for map canvas)
    // -------------------------------------------------------
    if (variable_struct_exists(_asset.meta, "preview_surf_clean") &&
        surface_exists(_asset.meta.preview_surf_clean)) {
        surface_free(_asset.meta.preview_surf_clean);
    }
    var _surf_clean = surface_create(_surf_w, _surf_h);
    surface_set_target(_surf_clean);
    draw_clear(_bg);
    for (var _dr2 = 0; _dr2 < _disp_rows; _dr2++) {
        var _band_c     = _ecm_prev_mode ? (_dr2 div _ecm_real_rows) : 0;
        var _real_row_c = _ecm_prev_mode ? (_dr2 mod _ecm_real_rows) : _dr2;
        for (var _dc2 = 0; _dc2 < _cols; _dc2++) {
            var _src_char_c = (_real_row_c * _cols) + _dc2;
            var _cx = _dc2 * _cell;
            var _cy = _dr2 * _cell;
            if (_ecm_prev_mode) {
                draw_set_color(_ecm_prev_bgs[_band_c]);
                draw_rectangle(_cx, _cy, _cx + _cell, _cy + _cell, false);
            }
            if (_src_char_c >= _total_chars) continue;
            var _src_base_c = _src_char_c * 8;
            if (_src_base_c + 8 > buffer_get_size(_asset.buffer)) continue;
            for (var _row = 0; _row < 8; _row++) {
                buffer_seek(_asset.buffer, buffer_seek_start, _src_base_c + _row);
                var _byte = buffer_read(_asset.buffer, buffer_u8);
                for (var _bit = 0; _bit < 8; _bit++) {
                    if (_byte & (0x80 >> _bit)) {
                        draw_set_color(_fg);
                        var _px = _cx + (_bit * _scale);
                        var _py = _cy + (_row * _scale);
                        draw_rectangle(_px, _py, _px + _scale, _py + _scale, false);
                    }
                }
            }
        }
    }
    draw_set_color(_grd);
    for (var _gc = 0; _gc <= _cols; _gc++)
        draw_line(_gc * _cell, 0, _gc * _cell, _surf_h);
    for (var _gr = 0; _gr <= _disp_rows; _gr++)
        draw_line(0, _gr * _cell, _surf_w, _gr * _cell);
    surface_reset_target();
    _asset.meta.preview_surf_clean = _surf_clean;

    // -------------------------------------------------------
    // SURFACE 3: preview_surf_mc (multicolour doubled-pixel rendering)
    // -------------------------------------------------------
    if (variable_struct_exists(_asset.meta, "preview_surf_mc") &&
        surface_exists(_asset.meta.preview_surf_mc)) {
        surface_free(_asset.meta.preview_surf_mc);
    }
    var _mc_bg   = variable_struct_exists(_asset.meta, "mc_bg")   ? _asset.meta.mc_bg   : 0;
    var _mc_col1 = variable_struct_exists(_asset.meta, "mc_col1") ? _asset.meta.mc_col1 : 1;
    var _mc_col2 = variable_struct_exists(_asset.meta, "mc_col2") ? _asset.meta.mc_col2 : 2;
    var _mc_cols = [
        scr_c64_pepto_colour(_mc_bg),     // 00 - background ($D021)
        scr_c64_pepto_colour(_mc_col1),   // 01 - $D022
        scr_c64_pepto_colour(_mc_col2),   // 10 - $D023
        scr_c64_pepto_colour(_mc_fg_idx), // 11 - colour RAM
    ];
    var _surf_mc = surface_create(_surf_w, _surf_h);
    surface_set_target(_surf_mc);
    draw_clear(scr_c64_pepto_colour(_mc_bg));
    for (var _char = 0; _char < _total_chars; _char++) {
        var _cx = (_char mod _cols) * _cell;
        var _cy = (_char div _cols) * _cell;
        for (var _row = 0; _row < 8; _row++) {
            buffer_seek(_asset.buffer, buffer_seek_start, (_char * 8) + _row);
            var _byte = buffer_read(_asset.buffer, buffer_u8);
            for (var _pair = 0; _pair < 4; _pair++) {
                var _bits = (_byte >> (6 - _pair * 2)) & 0x03;
                draw_set_color(_mc_cols[_bits]);
                var _px = _cx + (_pair * 2 * _scale);
                var _py = _cy + (_row * _scale);
                draw_rectangle(_px, _py, _px + (2 * _scale) - 1, _py + _scale - 1, false);
            }
        }
    }
    draw_set_color(_grd);
    for (var _gc = 0; _gc <= _cols; _gc++)
        draw_line(_gc * _cell, 0, _gc * _cell, _surf_h);
    for (var _gr = 0; _gr <= _rows; _gr++)
        draw_line(0, _gr * _cell, _surf_w, _gr * _cell);
    surface_reset_target();
    _asset.meta.preview_surf_mc = _surf_mc;

    show_debug_message("CHR PREVIEW: Built " + string(_cols) + "x" + string(_rows) + " grid (" + string(_total_chars) + " chars)");
}
