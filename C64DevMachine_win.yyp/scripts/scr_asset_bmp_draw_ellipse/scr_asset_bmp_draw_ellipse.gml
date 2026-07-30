/// @function scr_asset_bmp_draw_ellipse(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _filled, _shared_buf, _hr_fg)
/// @param {Bool} _hr_fg HiRes only: true = this stroke sets the cell's fg role/colour, false = bg role/colour.
function scr_asset_bmp_draw_ellipse(_asset, _x1, _y1, _x2, _y2, _col_idx, _mask_val, _filled, _shared_buf, _hr_fg = false) {
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
    var _cr = color_get_red(_col), _cg = color_get_green(_col), _cb = color_get_blue(_col);
    var _dmode = _asset.meta.dither_mode;
    var _dinv  = _asset.meta.dither_invert;
    
    var _ecx = (_x1 + _x2) / 2;
    var _ecy = (_y1 + _y2) / 2;
    // MC pixels are 2 world-px wide, so diameter-to-radius needs an extra /2
    // versus HiRes' square pixels.
    var _rx  = _is_hires ? max(1, (_x2 - _x1) / 2) : max(1, (_x2 - _x1) / 4);
    var _ry  = max(1, (_y2 - _y1) / 2);
    
    if (_filled) {
        for (var _py = -_ry; _py <= _ry; _py++) {
            var _row_rx = floor(sqrt(max(0, 1 - (_py * _py) / (_ry * _ry))) * _rx);
            for (var _mc = -_row_rx; _mc <= _row_rx; _mc++) {
                var _wpx = floor(_ecx + _mc * _step);
                var _wpy = floor(_ecy + _py);
                var _wsx = (_wpx div _step) * _step;
                if (_wsx < 0 || _wsx > _max_x || _wpy < 0 || _wpy >= 200) continue;
                var _wdraw = true;
                if (_dmode != "NONE") { _wdraw = scr_check_dither_mask(_dmode, _wsx, _wpy, _is_hires); if (_dinv) _wdraw = !_wdraw; }
                if (!_wdraw) continue;
                var _woff = (_wpy * 320 + _wsx) * 4;
                buffer_poke(_buf, _woff,     buffer_u8, _cr);
                buffer_poke(_buf, _woff + 1, buffer_u8, _cg);
                buffer_poke(_buf, _woff + 2, buffer_u8, _cb);
                _asset.meta.bg_mask[_wpy * 320 + _wsx] = _mask_val;
                if (_is_hires) {
                    var _hrca = (floor(_wpy / 8) * 40) + floor(_wsx / 8);
                    _asset.meta.hr_role_mask[_wpy * 320 + _wsx] = _hr_fg ? 1 : 0;
                    if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrca] = _col_idx; }
                    else        { _asset.meta.hr_cell_bg_col[_hrca] = _col_idx; }
                    scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrca);
                } else {
                    buffer_poke(_buf, _woff + 4, buffer_u8, _cr);
                    buffer_poke(_buf, _woff + 5, buffer_u8, _cg);
                    buffer_poke(_buf, _woff + 6, buffer_u8, _cb);
                    _asset.meta.bg_mask[_wpy * 320 + _wsx + 1] = _mask_val;
                }
            }
        }
    } else {
        // Midpoint ellipse — plot 4 symmetric points per step
        var _epx = 0, _epy = _ry;
        var _p1 = (_ry * _ry) - (_rx * _rx * _ry) + (0.25 * _rx * _rx);
        var _edx = 2 * _ry * _ry * _epx;
        var _edy = 2 * _rx * _rx * _epy;
        
        while (_edx < _edy) {
            var _pts = [
                [floor(_ecx + _epx * _step), floor(_ecy + _epy)],
                [floor(_ecx - _epx * _step), floor(_ecy + _epy)],
                [floor(_ecx + _epx * _step), floor(_ecy - _epy)],
                [floor(_ecx - _epx * _step), floor(_ecy - _epy)]
            ];
            for (var _pi = 0; _pi < 4; _pi++) {
                var _wpx = _pts[_pi][0], _wpy = _pts[_pi][1];
                var _wsx = (_wpx div _step) * _step;
                if (_wsx < 0 || _wsx > _max_x || _wpy < 0 || _wpy >= 200) continue;
                var _wdraw = true;
                if (_dmode != "NONE") { _wdraw = scr_check_dither_mask(_dmode, _wsx, _wpy, _is_hires); if (_dinv) _wdraw = !_wdraw; }
                if (!_wdraw) continue;
                var _woff = (_wpy * 320 + _wsx) * 4;
                buffer_poke(_buf, _woff,     buffer_u8, _cr);
                buffer_poke(_buf, _woff + 1, buffer_u8, _cg);
                buffer_poke(_buf, _woff + 2, buffer_u8, _cb);
                _asset.meta.bg_mask[_wpy * 320 + _wsx] = _mask_val;
                if (_is_hires) {
                    var _hrcb = (floor(_wpy / 8) * 40) + floor(_wsx / 8);
                    _asset.meta.hr_role_mask[_wpy * 320 + _wsx] = _hr_fg ? 1 : 0;
                    if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrcb] = _col_idx; }
                    else        { _asset.meta.hr_cell_bg_col[_hrcb] = _col_idx; }
                    scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrcb);
                } else {
                    buffer_poke(_buf, _woff + 4, buffer_u8, _cr);
                    buffer_poke(_buf, _woff + 5, buffer_u8, _cg);
                    buffer_poke(_buf, _woff + 6, buffer_u8, _cb);
                    _asset.meta.bg_mask[_wpy * 320 + _wsx + 1] = _mask_val;
                }
            }
            _epx++;
            _edx += 2 * _ry * _ry;
            if (_p1 < 0) {
                _p1 += _edx + _ry * _ry;
            } else {
                _epy--; _edy -= 2 * _rx * _rx;
                _p1 += _edx - _edy + _ry * _ry;
            }
        }
        
        var _p2 = _ry*_ry*(_epx+0.5)*(_epx+0.5) + _rx*_rx*(_epy-1)*(_epy-1) - _rx*_rx*_ry*_ry;
        while (_epy >= 0) {
            var _pts2 = [
                [floor(_ecx + _epx * _step), floor(_ecy + _epy)],
                [floor(_ecx - _epx * _step), floor(_ecy + _epy)],
                [floor(_ecx + _epx * _step), floor(_ecy - _epy)],
                [floor(_ecx - _epx * _step), floor(_ecy - _epy)]
            ];
            for (var _pi = 0; _pi < 4; _pi++) {
                var _wpx = _pts2[_pi][0], _wpy = _pts2[_pi][1];
                var _wsx = (_wpx div _step) * _step;
                if (_wsx < 0 || _wsx > _max_x || _wpy < 0 || _wpy >= 200) continue;
                var _wdraw = true;
                if (_dmode != "NONE") { _wdraw = scr_check_dither_mask(_dmode, _wsx, _wpy, _is_hires); if (_dinv) _wdraw = !_wdraw; }
                if (!_wdraw) continue;
                var _woff = (_wpy * 320 + _wsx) * 4;
                buffer_poke(_buf, _woff,     buffer_u8, _cr);
                buffer_poke(_buf, _woff + 1, buffer_u8, _cg);
                buffer_poke(_buf, _woff + 2, buffer_u8, _cb);
                _asset.meta.bg_mask[_wpy * 320 + _wsx] = _mask_val;
                if (_is_hires) {
                    var _hrcc = (floor(_wpy / 8) * 40) + floor(_wsx / 8);
                    _asset.meta.hr_role_mask[_wpy * 320 + _wsx] = _hr_fg ? 1 : 0;
                    if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrcc] = _col_idx; }
                    else        { _asset.meta.hr_cell_bg_col[_hrcc] = _col_idx; }
                    scr_asset_bmp_hr_repaint_cell_in_buffer(_asset, _buf, _hrcc);
                } else {
                    buffer_poke(_buf, _woff + 4, buffer_u8, _cr);
                    buffer_poke(_buf, _woff + 5, buffer_u8, _cg);
                    buffer_poke(_buf, _woff + 6, buffer_u8, _cb);
                    _asset.meta.bg_mask[_wpy * 320 + _wsx + 1] = _mask_val;
                }
            }
            _epy--;
            _edy -= 2 * _rx * _rx;
            if (_p2 > 0) {
                _p2 += _rx * _rx - _edy;
            } else {
                _epx++; _edx += 2 * _ry * _ry;
                _p2 += _edx - _edy + _rx * _rx;
            }
        }
    }
    
    if (_own_buf) {
        buffer_set_surface(_buf, _asset.meta.preview_surf, 0);
        buffer_delete(_buf);
    }
}