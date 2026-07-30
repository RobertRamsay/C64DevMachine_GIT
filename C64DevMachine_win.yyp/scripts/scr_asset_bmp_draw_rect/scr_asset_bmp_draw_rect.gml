/// @function scr_asset_bmp_draw_rect(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _filled, _shared_buf, _hr_fg)
/// @param {Bool} _hr_fg HiRes only: true = this stroke sets the cell's fg role/colour, false = bg role/colour.
function scr_asset_bmp_draw_rect(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _filled, _shared_buf, _hr_fg = false) {
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _max_x    = _is_hires ? 319 : 318;
    var _own_buf = false;
    if (_shared_buf == undefined) {
        _own_buf = true;
    } else {
        _own_buf = false;
    }
    var _buf;
    if (_own_buf) {
        _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
        buffer_get_surface(_buf, _asset.meta.preview_surf, 0);
    } else {
        _buf = _shared_buf;
    }
    var _col = scr_c64_pepto_colour(_col_idx);
    var _r = color_get_red(_col), _g = color_get_green(_col), _b = color_get_blue(_col);
    
    for (var _y = _y1; _y <= _y2; _y++) {
        for (var _x = _x1; _x <= _x2; _x += _step) {
            var _on_edge = _is_hires
                ? (_x == _x1 || _x == _x2 || _y == _y1 || _y == _y2)
                : (_x == _x1 || _x >= _x2 - 1 || _y == _y1 || _y == _y2);
            if (!_filled && !_on_edge) continue;
            if (_x < 0 || _x > _max_x || _y < 0 || _y >= 200) continue;
            var _draw = true;
            if (_asset.meta.dither_mode != "NONE") {
                _draw = scr_check_dither_mask(_asset.meta.dither_mode, _x, _y, _is_hires);
                if (_asset.meta.dither_invert) _draw = !_draw;
            }
            if (_draw) {
                var _off = (_y * 320 + _x) * 4;
                buffer_poke(_buf, _off,     buffer_u8, _r);
                buffer_poke(_buf, _off + 1, buffer_u8, _g);
                buffer_poke(_buf, _off + 2, buffer_u8, _b);
                _asset.meta.bg_mask[_y * 320 + _x] = _mask_val;
                if (_is_hires) {
                    var _hrc = (floor(_y / 8) * 40) + floor(_x / 8);
                    _asset.meta.hr_role_mask[_y * 320 + _x] = _hr_fg ? 1 : 0;
                    if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrc] = _col_idx; }
                    else        { _asset.meta.hr_cell_bg_col[_hrc] = _col_idx; }
                    scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrc);
                } else {
                    buffer_poke(_buf, _off + 4, buffer_u8, _r);
                    buffer_poke(_buf, _off + 5, buffer_u8, _g);
                    buffer_poke(_buf, _off + 6, buffer_u8, _b);
                    _asset.meta.bg_mask[_y * 320 + _x + 1] = _mask_val;
                }
            }
        }
    }
    if (_own_buf) {
        buffer_set_surface(_buf, _asset.meta.preview_surf, 0);
        buffer_delete(_buf);
    }
}