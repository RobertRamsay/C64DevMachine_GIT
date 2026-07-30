/// @function scr_asset_bmp_draw_line(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _shared_buf, _hr_fg)
/// @param {Bool} _hr_fg HiRes only: true = this stroke sets the cell's fg role/colour, false = bg role/colour.
function scr_asset_bmp_draw_line(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _shared_buf, _hr_fg = false) {
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _max_x    = _is_hires ? 319 : 318;
    // When a shared buffer is passed the caller owns the surface I/O; we only
    // poke. When it is not passed we own a private buffer (legacy path).
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
    var _brad = _asset.meta.brush_size;
    var _dmode = _asset.meta.dither_mode;
    var _dinv  = _asset.meta.dither_invert;

    // Bresenham — MC steps 2 world-px per unit (one MC pixel pair);
    // HiRes steps 1, since every pixel is independently addressable.
    var _dx_mc = abs((_x2 div _step) - (_x1 div _step));
    var _dy    = abs(_y2 - _y1);
    var _sx    = (_x1 < _x2) ? _step : -_step;
    var _sy    = (_y1 < _y2) ? 1 : -1;
    var _err   = _dx_mc - _dy;
    var _cx    = (_x1 div _step) * _step;
    var _cy    = _y1;
    var _ex    = (_x2 div _step) * _step;

    for (var _steps = 0; _steps < 640; _steps++) {

        // Stamp brush at this Bresenham point
        if (_brad == 0) {
            // Single pixel (HiRes) or MC pixel pair
            if (_cx >= 0 && _cx <= _max_x && _cy >= 0 && _cy < 200) {
                var _draw = true;
                if (_dmode != "NONE") {
                    _draw = scr_check_dither_mask(_dmode, _cx, _cy, _is_hires);
                    if (_dinv) _draw = !_draw;
                }
                if (_draw) {
                    var _off = (_cy * 320 + _cx) * 4;
                    buffer_poke(_buf, _off,     buffer_u8, _r);
                    buffer_poke(_buf, _off + 1, buffer_u8, _g);
                    buffer_poke(_buf, _off + 2, buffer_u8, _b);
                    _asset.meta.bg_mask[_cy * 320 + _cx] = _mask_val;
                    if (_is_hires) {
                        var _hrc1 = (floor(_cy / 8) * 40) + floor(_cx / 8);
                        _asset.meta.hr_role_mask[_cy * 320 + _cx] = _hr_fg ? 1 : 0;
                        if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrc1] = _col_idx; }
                        else        { _asset.meta.hr_cell_bg_col[_hrc1] = _col_idx; }
                        scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrc1);
                    } else {
                        buffer_poke(_buf, _off + 4, buffer_u8, _r);
                        buffer_poke(_buf, _off + 5, buffer_u8, _g);
                        buffer_poke(_buf, _off + 6, buffer_u8, _b);
                        _asset.meta.bg_mask[_cy * 320 + _cx + 1] = _mask_val;
                    }
                }
            }
        } else {
            // Circle brush — iterate pixel blocks in radius.
            // MC pixels are 2 world-px wide and 1 tall, so the X term is
            // doubled to correct the 2:1 aspect. HiRes pixels are square,
            // so no correction is needed.
            for (var _bmy = -_brad; _bmy <= _brad; _bmy++) {
                for (var _bmx = -_brad; _bmx <= _brad; _bmx++) {
                    var _ndx = _is_hires ? (_bmx / _brad) : ((_bmx * 2) / _brad);
                    var _ndy = _bmy / _brad;
                    if (_ndx * _ndx + _ndy * _ndy > 1.0) continue;
                    var _tx = ((_cx + _bmx * _step) div _step) * _step;
                    var _ty = _cy + _bmy;
                    if (_tx < 0 || _tx > _max_x || _ty < 0 || _ty >= 200) continue;
                    var _draw = true;
                    if (_dmode != "NONE") {
                        _draw = scr_check_dither_mask(_dmode, _tx, _ty, _is_hires);
                        if (_dinv) _draw = !_draw;
                    }
                    if (_draw) {
                        var _off = (_ty * 320 + _tx) * 4;
                        buffer_poke(_buf, _off,     buffer_u8, _r);
                        buffer_poke(_buf, _off + 1, buffer_u8, _g);
                        buffer_poke(_buf, _off + 2, buffer_u8, _b);
                        _asset.meta.bg_mask[_ty * 320 + _tx] = _mask_val;
                       if (_is_hires) {
                            var _hrc2 = (floor(_ty / 8) * 40) + floor(_tx / 8);
                            _asset.meta.hr_role_mask[_ty * 320 + _tx] = _hr_fg ? 1 : 0;
                            if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrc2] = _col_idx; }
                            else        { _asset.meta.hr_cell_bg_col[_hrc2] = _col_idx; }
                            scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrc2);
                        } else {
                            buffer_poke(_buf, _off + 4, buffer_u8, _r);
                            buffer_poke(_buf, _off + 5, buffer_u8, _g);
                            buffer_poke(_buf, _off + 6, buffer_u8, _b);
                            _asset.meta.bg_mask[_ty * 320 + _tx + 1] = _mask_val;
                        }
                    }
                }
            }
        }

        if (_cx == _ex && _cy == _y2) break;
        var _e2 = 2 * _err;
        if (_e2 > -_dy)    { _err -= _dy;    _cx += _sx; }
        if (_e2 <  _dx_mc) { _err += _dx_mc; _cy += _sy; }
    }
    if (_own_buf) {
        buffer_set_surface(_buf, _asset.meta.preview_surf, 0);
        buffer_delete(_buf);
    }
}