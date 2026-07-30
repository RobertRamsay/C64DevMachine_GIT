/// @function scr_vbmp_raster_line(_x0, _y0, _x1, _y1)
/// Bresenham. Returns array of [x,y] points.
function scr_vbmp_raster_line(_x0, _y0, _x1, _y1) {
    var _pts = [];
    var _dx = abs(_x1 - _x0);
    var _dy = abs(_y1 - _y0);
    var _sx = (_x0 < _x1) ? 1 : -1;
    var _sy = (_y0 < _y1) ? 1 : -1;
    var _err = _dx - _dy;
    var _cx = _x0, _cy = _y0;
    var _guard = 0;
    while (_guard < 2048) {
        array_push(_pts, [_cx, _cy]);
        if (_cx == _x1 && _cy == _y1) break;
        var _e2 = _err * 2;
        if (_e2 > -_dy) { _err -= _dy; _cx += _sx; }
        if (_e2 <  _dx) { _err += _dx; _cy += _sy; }
        _guard++;
    }
    return _pts;
}

/// @function scr_vbmp_raster_rect(_x0, _y0, _x1, _y1)
/// Four edges (outline).
function scr_vbmp_raster_rect(_x0, _y0, _x1, _y1) {
    var _lx = min(_x0, _x1), _rx = max(_x0, _x1);
    var _ty = min(_y0, _y1), _by = max(_y0, _y1);
    var _pts = [];
    for (var _x = _lx; _x <= _rx; _x++) { array_push(_pts, [_x, _ty]); array_push(_pts, [_x, _by]); }
    for (var _y = _ty; _y <= _by; _y++) { array_push(_pts, [_lx, _y]); array_push(_pts, [_rx, _y]); }
    return _pts;
}

/// @function scr_vbmp_raster_rectfill(_x0, _y0, _x1, _y1)
function scr_vbmp_raster_rectfill(_x0, _y0, _x1, _y1) {
    var _lx = min(_x0, _x1), _rx = max(_x0, _x1);
    var _ty = min(_y0, _y1), _by = max(_y0, _y1);
    var _pts = [];
    for (var _y = _ty; _y <= _by; _y++) {
        for (var _x = _lx; _x <= _rx; _x++) array_push(_pts, [_x, _y]);
    }
    return _pts;
}

/// @function scr_vbmp_raster_ellipse(_cx, _cy, _rx, _ry)
/// Midpoint ellipse outline.
function scr_vbmp_raster_ellipse(_cx, _cy, _rx, _ry) {
    var _pts = [];
    if (_rx < 1) _rx = 1;
    if (_ry < 1) _ry = 1;
    var _x = 0, _y = _ry;
    var _rx2 = _rx * _rx, _ry2 = _ry * _ry;
    var _px = 0, _py = 2 * _rx2 * _y;
    var _p;
    var _push4 = function(_a, _cx, _cy, _x, _y) {
        array_push(_a, [_cx + _x, _cy + _y]);
        array_push(_a, [_cx - _x, _cy + _y]);
        array_push(_a, [_cx + _x, _cy - _y]);
        array_push(_a, [_cx - _x, _cy - _y]);
    };
    _push4(_pts, _cx, _cy, _x, _y);
    _p = round(_ry2 - (_rx2 * _ry) + (0.25 * _rx2));
    while (_px < _py) {
        _x++; _px += 2 * _ry2;
        if (_p < 0) { _p += _ry2 + _px; }
        else { _y--; _py -= 2 * _rx2; _p += _ry2 + _px - _py; }
        _push4(_pts, _cx, _cy, _x, _y);
    }
    _p = round(_ry2 * (_x + 0.5) * (_x + 0.5) + _rx2 * (_y - 1) * (_y - 1) - _rx2 * _ry2);
    while (_y > 0) {
        _y--; _py -= 2 * _rx2;
        if (_p > 0) { _p += _rx2 - _py; }
        else { _x++; _px += 2 * _ry2; _p += _rx2 - _py + _px; }
        _push4(_pts, _cx, _cy, _x, _y);
    }
    return _pts;
}

/// @function scr_vbmp_raster_ellipsefill(_cx, _cy, _rx, _ry)
/// Scanline fill using the ellipse equation.
function scr_vbmp_raster_ellipsefill(_cx, _cy, _rx, _ry) {
    var _pts = [];
    if (_rx < 1) _rx = 1;
    if (_ry < 1) _ry = 1;
    var _rx2 = _rx * _rx, _ry2 = _ry * _ry;
    for (var _dy = -_ry; _dy <= _ry; _dy++) {
        // half-width at this row: rx * sqrt(1 - dy^2/ry^2)
        var _hw = floor(_rx * sqrt(max(0, 1 - (_dy * _dy) / _ry2)));
        for (var _dx = -_hw; _dx <= _hw; _dx++) {
            array_push(_pts, [_cx + _dx, _cy + _dy]);
        }
    }
    return _pts;
}