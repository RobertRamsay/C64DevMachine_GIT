/// @function scr_vbmp_preview_points(_op, _x0, _y0, _x1, _y1)
/// Rasterise a pending draw op into an array of [px, py] MC-snapped pixel
/// coords, matching how scr_vbmp_replay_to_surface plots each shape. Used by
/// the editor's live preview so the rubber-band shows real pixels, not a box.
/// Shape math runs in unsnapped space; X is snapped to the 2px MC grid only
/// when a point is emitted, so step/termination logic can't drift.
function scr_vbmp_preview_points(_op, _x0, _y0, _x1, _y1) {
    var _pts = [];

    if (_op == "line") {
        // Standard integer Bresenham in raw pixel space, unit steps. Snap X to
        // the MC grid only on push. Stepping the raw coordinate (not a snapped
        // one) keeps the termination test valid, so the line can't overrun.
        var _cx = _x0;
        var _cy = _y0;
        var _dx = abs(_x1 - _x0);
        var _dy = abs(_y1 - _y0);
        var _sx = (_x0 < _x1) ? 1 : -1;
        var _sy = (_y0 < _y1) ? 1 : -1;
        var _err = _dx - _dy;
        var _guard = 0;
        while (_guard < 8192) {
            array_push(_pts, [(_cx div 2) * 2, _cy]);
            if (_cx == _x1 && _cy == _y1) break;
            var _e2 = _err * 2;
            if (_e2 > -_dy) { _err -= _dy; _cx += _sx; }
            if (_e2 <  _dx) { _err += _dx; _cy += _sy; }
            _guard += 1;
        }
    }
    else if (_op == "rect" || _op == "rectfill") {
        var _lx = min(_x0, _x1);
        var _rx = max(_x0, _x1);
        var _ty = min(_y0, _y1);
        var _by = max(_y0, _y1);
        if (_op == "rect") {
            var _xx = _lx;
            while (_xx <= _rx) {
                array_push(_pts, [(_xx div 2) * 2, _ty]);
                array_push(_pts, [(_xx div 2) * 2, _by]);
                _xx += 2;
            }
            var _yy = _ty;
            while (_yy <= _by) {
                array_push(_pts, [(_lx div 2) * 2, _yy]);
                array_push(_pts, [(_rx div 2) * 2, _yy]);
                _yy += 1;
            }
        } else {
            var _yy = _ty;
            while (_yy <= _by) {
                var _xx = _lx;
                while (_xx <= _rx) {
                    array_push(_pts, [(_xx div 2) * 2, _yy]);
                    _xx += 2;
                }
                _yy += 1;
            }
        }
    }
    else if (_op == "ellipse" || _op == "ellipsefill") {
        // Centre/radius derived the same way as the commit block.
        var _ecx = (_x0 + _x1) div 2;
        var _ecy = (_y0 + _y1) div 2;
        var _erx = max(1, abs(_x1 - _x0) div 4);
        var _ery = max(1, abs(_y1 - _y0) div 2);

        // Pixel radii: rx is in MC cells, so *2 to reach raw X pixels.
        var _rxp = _erx * 2;
        var _ryp = _ery;

        if (_op == "ellipsefill") {
            // Scan each Y row ONCE. For row dy, solve the half-width in X from
            // the ellipse equation, then fill centre-out to that width. This
            // removes the duplicate/oblique rows the parametric sweep produced.
            var _dyi = -_ryp;
            while (_dyi <= _ryp) {
                // x half-extent in pixels for this row.
                var _norm = 1.0 - (_dyi * _dyi) / (_ryp * _ryp);
                if (_norm < 0) _norm = 0;
                var _halfx = round(_rxp * sqrt(_norm));
                var _px = -_halfx;
                while (_px <= _halfx) {
                    array_push(_pts, [((_ecx + _px) div 2) * 2, _ecy + _dyi]);
                    _px += 2;
                }
                _dyi += 1;
            }
        } else {
            // Outline: parametric sweep is fine for the edge (no fill overlap).
            var _steps = 160;
            var _i = 0;
            while (_i < _steps) {
                var _ang = (_i / _steps) * 2 * pi;
                var _ex = _ecx + round(cos(_ang) * _rxp);
                var _ey = _ecy + round(sin(_ang) * _ryp);
                array_push(_pts, [(_ex div 2) * 2, _ey]);
                _i += 1;
            }
        }
    }

    return _pts;
}