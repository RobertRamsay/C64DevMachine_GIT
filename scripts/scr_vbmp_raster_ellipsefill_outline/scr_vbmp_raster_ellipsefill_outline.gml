/// @function scr_vbmp_raster_ellipsefill_outline(_cx, _cy, _rx, _ry)
/// Solid ellipse fill whose SILHOUETTE is identical to scr_vbmp_raster_ellipse
/// (the midpoint outline). Instead of solving the ellipse equation per row
/// (which gives a subtly different edge), it rasterises the midpoint outline
/// and then fills each scanline between that outline's own min/max X. Result:
/// the filled shape and the outline shape share the exact same boundary.
function scr_vbmp_raster_ellipsefill_outline(_cx, _cy, _rx, _ry) {
    // Get the outline points — this is the shape we want the fill to match.
    var _outline = scr_vbmp_raster_ellipse(_cx, _cy, _rx, _ry);

    // Per-row X extents from the outline. Track min and max X for each Y.
    var _row_min = ds_map_create();
    var _row_max = ds_map_create();
    var _y_lo = 999999;
    var _y_hi = -999999;

    var _n = array_length(_outline);
    for (var _i = 0; _i < _n; _i++) {
        var _ox = _outline[_i][0];
        var _oy = _outline[_i][1];
        var _key = string(_oy);
        if (ds_map_exists(_row_min, _key)) {
            if (_ox < _row_min[? _key]) _row_min[? _key] = _ox;
            if (_ox > _row_max[? _key]) _row_max[? _key] = _ox;
        } else {
            _row_min[? _key] = _ox;
            _row_max[? _key] = _ox;
        }
        if (_oy < _y_lo) _y_lo = _oy;
        if (_oy > _y_hi) _y_hi = _oy;
    }

    // Fill each row between its own min/max X, stepping X by 2 (MC pairs).
    var _pts = [];
    var _yy = _y_lo;
    while (_yy <= _y_hi) {
        var _key2 = string(_yy);
        if (ds_map_exists(_row_min, _key2)) {
            var _xl = _row_min[? _key2];
            var _xr = _row_max[? _key2];
            var _xx = _xl;
            while (_xx <= _xr) {
                array_push(_pts, [_xx, _yy]);
                _xx += 2;
            }
        }
        _yy += 1;
    }

    ds_map_destroy(_row_min);
    ds_map_destroy(_row_max);
    return _pts;
}