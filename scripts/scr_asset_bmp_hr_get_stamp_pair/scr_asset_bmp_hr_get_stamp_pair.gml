/// @function scr_asset_bmp_hr_get_stamp_pair(_asset)
/// @desc HiRes only. Scans the current grab stamp (grab_surf) and returns its
///       two most common colours among opaque pixels, as { fg: <idx>, bg: <idx> }.
///       A captured stamp can span multiple source cells, each with its own
///       pair — rather than trying to preserve each source cell's individual
///       pair (which the destination may not have room for once merged with
///       existing content), every cell the stamp touches gets this SAME pair.
function scr_asset_bmp_hr_get_stamp_pair(_asset) {
    var _result = { fg: 1, bg: 0 };
    if (!surface_exists(_asset.meta.grab_surf)) return _result;
    var _w = _asset.meta.grab_w;
    var _h = _asset.meta.grab_h;
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _asset.meta.grab_surf, 0);
    var _pepto_r = array_create(16, 0), _pepto_g = array_create(16, 0), _pepto_b = array_create(16, 0);
    for (var _c = 0; _c < 16; _c++) {
        var _pc = scr_c64_pepto_colour(_c);
        _pepto_r[_c] = color_get_red(_pc);
        _pepto_g[_c] = color_get_green(_pc);
        _pepto_b[_c] = color_get_blue(_pc);
    }
    var _counts = array_create(16, 0);
    for (var _yy = 0; _yy < _h; _yy++) {
        for (var _xx = 0; _xx < _w; _xx++) {
            var _off = (_yy * _w + _xx) * 4;
            if (buffer_peek(_buf, _off + 3, buffer_u8) == 0) continue; // transparent
            var _r = buffer_peek(_buf, _off, buffer_u8);
            var _g = buffer_peek(_buf, _off + 1, buffer_u8);
            var _b = buffer_peek(_buf, _off + 2, buffer_u8);
            var _best = 0, _min_dist = 999999;
            for (var _c2 = 0; _c2 < 16; _c2++) {
                var _dist = abs(_r - _pepto_r[_c2]) + abs(_g - _pepto_g[_c2]) + abs(_b - _pepto_b[_c2]);
                if (_dist < _min_dist) { _min_dist = _dist; _best = _c2; }
            }
            _counts[_best]++;
        }
    }
    buffer_delete(_buf);
    var _win_a = -1, _win_b = -1, _cnt_a = 0, _cnt_b = 0;
    for (var _c3 = 0; _c3 < 16; _c3++) {
        if (_counts[_c3] > _cnt_a) {
            _cnt_b = _cnt_a; _win_b = _win_a;
            _cnt_a = _counts[_c3]; _win_a = _c3;
        } else if (_counts[_c3] > _cnt_b) {
            _cnt_b = _counts[_c3]; _win_b = _c3;
        }
    }
    if (_win_a == -1) return _result;
    _result.fg = _win_a;
    _result.bg = (_win_b != -1) ? _win_b : _win_a;
    return _result;
}