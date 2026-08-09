/// @function scr_asset_bmp_gradient_fill(_asset, _x1, _y1, _x2, _y2, _col_start, _col_end)
/// Amiga Dev Machine style gradient fill for the regular (KLA) bitmap editor.
/// Floods the contiguous region matching the seed pixel (_x1,_y1), then paints
/// every pixel in that region _col_start or _col_end by projecting its position
/// onto the drawn line (_x1,_y1)->(_x2,_y2) and thresholding against an 8x8
/// ordered Bayer matrix — a directional dithered gradient, not a fixed-ratio
/// pattern. _col_start sits at the seed end (projection 0), _col_end at the
/// drag-release end (projection 1). Works in both MC and HiRes.
function scr_asset_bmp_gradient_fill(_asset, _x1, _y1, _x2, _y2, _col_start, _col_end) {
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _max_x    = _is_hires ? 319 : 318;
    if (!_is_hires) _x1 = (_x1 div 2) * 2; // MC snap seed

    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _asset.meta.preview_surf, 0);

    // Standard 8x8 ordered Bayer matrix, 64 threshold levels — same table as
    // scr_check_dither_mask's _bayer_hr, sampled with a +0.5 centring offset
    // so the 0..63 levels map evenly across the 0..1 projection range.
    static _bayer8 = [
         0,32, 8,40, 2,34,10,42,
        48,16,56,24,50,18,58,26,
        12,44, 4,36,14,46, 6,38,
        60,28,52,20,62,30,54,22,
         3,35,11,43, 1,33, 9,41,
        51,19,59,27,49,17,57,25,
        15,47, 7,39,13,45, 5,37,
        63,31,55,23,61,29,53,21
    ];

    var _start_rgb = scr_c64_pepto_colour(_col_start);
    var _end_rgb   = scr_c64_pepto_colour(_col_end);
    var _ar = color_get_red(_start_rgb), _ag = color_get_green(_start_rgb), _ab = color_get_blue(_start_rgb);
    var _br = color_get_red(_end_rgb),   _bg = color_get_green(_end_rgb),   _bb = color_get_blue(_end_rgb);

    // Read target (seed) colour.
    var _off0 = (_y1 * 320 + _x1) * 4;
    var _tr = buffer_peek(_buf, _off0,     buffer_u8);
    var _tg = buffer_peek(_buf, _off0 + 1, buffer_u8);
    var _tb = buffer_peek(_buf, _off0 + 2, buffer_u8);

    // Nothing to change if both gradient colours already equal the seed.
    if (_ar == _br && _ag == _bg && _ab == _bb && _tr == _ar && _tg == _ag && _tb == _ab) {
        buffer_delete(_buf);
        return;
    }

    var _dx = _x2 - _x1;
    var _dy = _y2 - _y1;
    var _len_sq = (_dx * _dx) + (_dy * _dy);
    if (_len_sq < 1) _len_sq = 1; // zero-length drag -> single hard threshold at 0.5

    // PASS 1 — run-based scanline flood identifies the connected region into
    // a flat [x0,y0,x1,y1,...] list. Same shape as scr_asset_bmp_flood_fill,
    // but nothing is painted here: the gradient colour depends on x/y, not
    // just region membership, so painting happens in PASS 2 once the whole
    // region is known.
    var _visited = array_create(64000, false);
    var _region  = [];
    var _stack = ds_stack_create();
    ds_stack_push(_stack, _x1, _y1);

    while (!ds_stack_empty(_stack)) {
        var _cy = ds_stack_pop(_stack);
        var _cx = ds_stack_pop(_stack);

        if (_cx < 0 || _cx > _max_x || _cy < 0 || _cy >= 200) continue;
        if (_visited[_cy * 320 + _cx]) continue;

        var _soff = (_cy * 320 + _cx) * 4;
        if (buffer_peek(_buf, _soff,     buffer_u8) != _tr) continue;
        if (buffer_peek(_buf, _soff + 1, buffer_u8) != _tg) continue;
        if (buffer_peek(_buf, _soff + 2, buffer_u8) != _tb) continue;

        var _lx = _cx;
        while (_lx - _step >= 0) {
            var _lo = (_cy * 320 + _lx - _step) * 4;
            if (_visited[_cy * 320 + _lx - _step]) break;
            if (buffer_peek(_buf, _lo,     buffer_u8) != _tr) break;
            if (buffer_peek(_buf, _lo + 1, buffer_u8) != _tg) break;
            if (buffer_peek(_buf, _lo + 2, buffer_u8) != _tb) break;
            _lx -= _step;
        }

        var _above_in = false;
        var _below_in = false;
        var _x = _lx;
        while (_x <= _max_x) {
            var _o = (_cy * 320 + _x) * 4;
            if (_visited[_cy * 320 + _x]) break;
            if (buffer_peek(_buf, _o,     buffer_u8) != _tr) break;
            if (buffer_peek(_buf, _o + 1, buffer_u8) != _tg) break;
            if (buffer_peek(_buf, _o + 2, buffer_u8) != _tb) break;
            _visited[_cy * 320 + _x] = true;
            array_push(_region, _x, _cy);

            if (_cy > 0) {
                var _ao = ((_cy - 1) * 320 + _x) * 4;
                var _amatch = !_visited[(_cy - 1) * 320 + _x]
                           && (buffer_peek(_buf, _ao,     buffer_u8) == _tr)
                           && (buffer_peek(_buf, _ao + 1, buffer_u8) == _tg)
                           && (buffer_peek(_buf, _ao + 2, buffer_u8) == _tb);
                if (_amatch && !_above_in) {
                    ds_stack_push(_stack, _x, _cy - 1);
                    _above_in = true;
                } else if (!_amatch) {
                    _above_in = false;
                }
            }

            if (_cy < 199) {
                var _bo = ((_cy + 1) * 320 + _x) * 4;
                var _bmatch = !_visited[(_cy + 1) * 320 + _x]
                           && (buffer_peek(_buf, _bo,     buffer_u8) == _tr)
                           && (buffer_peek(_buf, _bo + 1, buffer_u8) == _tg)
                           && (buffer_peek(_buf, _bo + 2, buffer_u8) == _tb);
                if (_bmatch && !_below_in) {
                    ds_stack_push(_stack, _x, _cy + 1);
                    _below_in = true;
                } else if (!_bmatch) {
                    _below_in = false;
                }
            }

            _x += _step;
        }
    }
    ds_stack_destroy(_stack);

    // PASS 2 — paint every visited pixel _col_start/_col_end by projecting
    // onto the drawn line and thresholding against the Bayer matrix.
    var _ri = 0;
    var _region_count = array_length(_region);
    while (_ri < _region_count) {
        var _rx = _region[_ri];
        var _ry = _region[_ri + 1];
        _ri += 2;

        var _proj = (((_rx - _x1) * _dx) + ((_ry - _y1) * _dy)) / _len_sq;
        _proj = clamp(_proj, 0, 1);
        var _bthr = (_bayer8[(_ry mod 8) * 8 + (_rx mod 8)] + 0.5) / 64;
        var _use_end = (_proj >= _bthr);

        var _wr, _wg, _wb, _wcol;
        if (_use_end) { _wr = _br; _wg = _bg; _wb = _bb; _wcol = _col_end;   }
        else          { _wr = _ar; _wg = _ag; _wb = _ab; _wcol = _col_start; }

        var _o = (_ry * 320 + _rx) * 4;
        buffer_poke(_buf, _o,     buffer_u8, _wr);
        buffer_poke(_buf, _o + 1, buffer_u8, _wg);
        buffer_poke(_buf, _o + 2, buffer_u8, _wb);
        _asset.meta.bg_mask[_ry * 320 + _rx] = 1;

        if (_is_hires) {
            // Role follows which of the cell's 2 allowed colours (fg =
            // active_color, bg = secondary_color) actually landed on this
            // pixel — same fg/bg convention scr_asset_bmp_draw_line/_rect/
            // _ellipse use, so a gradient that spans both colours in one
            // 8x8 cell still gets a correct per-pixel role, not "always fg".
            var _hrcf  = (floor(_ry / 8) * 40) + floor(_rx / 8);
            var _hrfg  = (_wcol == _asset.meta.active_color);
            _asset.meta.hr_role_mask[_ry * 320 + _rx] = _hrfg ? 1 : 0;
            if (_hrfg) { _asset.meta.hr_cell_fg_col[_hrcf] = _wcol; }
            else       { _asset.meta.hr_cell_bg_col[_hrcf] = _wcol; }
        } else {
            buffer_poke(_buf, _o + 4, buffer_u8, _wr);
            buffer_poke(_buf, _o + 5, buffer_u8, _wg);
            buffer_poke(_buf, _o + 6, buffer_u8, _wb);
            _asset.meta.bg_mask[_ry * 320 + _rx + 1] = 1;
        }
    }

    buffer_set_surface(_buf, _asset.meta.preview_surf, 0);
    buffer_delete(_buf);
}
