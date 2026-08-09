/// @function scr_asset_bmp_gradient_fill(_asset, _x1, _y1, _x2, _y2, _col_start, _col_end, _custom_stops)
/// Amiga Dev Machine style gradient fill for the regular (KLA) bitmap editor.
/// Floods the contiguous region matching the seed pixel (_x1,_y1), then paints
/// every pixel in that region by projecting its position onto the drawn line
/// (_x1,_y1)->(_x2,_y2) and thresholding an ordered Bayer matrix — a
/// directional dithered gradient, not a fixed-ratio pattern.
///
/// @param {Array<Real>} [_custom_stops] Optional. When provided (2+ colour
///        indices), the gradient runs through ALL of them in order instead of
///        just _col_start->_col_end — _col_start/_col_end are still used as
///        the flood seed match target but are otherwise ignored once a custom
///        stop list is given. Undefined/omitted -> plain 2-colour gradient.
///
/// MC uses the same 4-column x 8-row (32-level) ordered Bayer matrix as
/// scr_check_dither_mask's BAYER_* presets, sampled on the MC pair column —
/// NOT the 8x8 HiRes matrix naively indexed by raw x, which only ever hits 4
/// of its 8 columns in MC (x is always even) and produces coarser, blockier
/// banding. HiRes uses the full 8x8/64-level matrix, one threshold per pixel.
function scr_asset_bmp_gradient_fill(_asset, _x1, _y1, _x2, _y2, _col_start, _col_end, _custom_stops = undefined) {
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _max_x    = _is_hires ? 319 : 318;
    if (!_is_hires) _x1 = (_x1 div 2) * 2; // MC snap seed

    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _asset.meta.preview_surf, 0);

    // Standard 8x8 ordered Bayer matrix, 64 threshold levels — HiRes only.
    static _bayer_hr = [
         0,32, 8,40, 2,34,10,42,
        48,16,56,24,50,18,58,26,
        12,44, 4,36,14,46, 6,38,
        60,28,52,20,62,30,54,22,
         3,35,11,43, 1,33, 9,41,
        51,19,59,27,49,17,57,25,
        15,47, 7,39,13,45, 5,37,
        63,31,55,23,61,29,53,21
    ];
    // MC-aware Bayer: 4 columns (MC pair index) x 8 rows = 32 threshold
    // levels. Identical table to scr_check_dither_mask's _bayer_mc, so a
    // gradient's dither grain matches the fixed-ratio dither tool exactly.
    static _bayer_mc = [
         0, 8, 2,10,
        24,16,26,18,
        12, 4,14, 6,
        28,20,30,22,
         3,11, 1, 9,
        27,19,25,17,
        15, 7,13, 5,
        31,23,29,21
    ];

    // Build the stop list: custom multi-colour run if given, else the plain
    // 2-colour start->end gradient.
    var _stops = (is_array(_custom_stops) && array_length(_custom_stops) >= 2) ? _custom_stops : [_col_start, _col_end];
    var _n_stops = array_length(_stops);
    var _stop_r = array_create(_n_stops), _stop_g = array_create(_n_stops), _stop_b = array_create(_n_stops);
    for (var _si = 0; _si < _n_stops; _si++) {
        var _srgb = scr_c64_pepto_colour(_stops[_si]);
        _stop_r[_si] = color_get_red(_srgb);
        _stop_g[_si] = color_get_green(_srgb);
        _stop_b[_si] = color_get_blue(_srgb);
    }

    // Read target (seed) colour.
    var _off0 = (_y1 * 320 + _x1) * 4;
    var _tr = buffer_peek(_buf, _off0,     buffer_u8);
    var _tg = buffer_peek(_buf, _off0 + 1, buffer_u8);
    var _tb = buffer_peek(_buf, _off0 + 2, buffer_u8);

    // Nothing to change if every stop already equals the seed colour.
    var _all_match_seed = true;
    for (var _sci = 0; _sci < _n_stops && _all_match_seed; _sci++) {
        if (_stop_r[_sci] != _tr || _stop_g[_sci] != _tg || _stop_b[_sci] != _tb) _all_match_seed = false;
    }
    if (_all_match_seed) {
        buffer_delete(_buf);
        return;
    }

    var _dx = _x2 - _x1;
    var _dy = _y2 - _y1;
    var _len_sq = (_dx * _dx) + (_dy * _dy);
    if (_len_sq < 1) _len_sq = 1; // zero-length drag -> single hard threshold at the midpoint

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

    // PASS 2 — paint every visited pixel by projecting onto the drawn line,
    // picking the two adjacent stops that projection falls between, then
    // dithering between just those two via the Bayer threshold.
    var _ri = 0;
    var _region_count = array_length(_region);
    var _last_seg = _n_stops - 2; // highest valid "lower" stop index
    while (_ri < _region_count) {
        var _rx = _region[_ri];
        var _ry = _region[_ri + 1];
        _ri += 2;

        var _proj = (((_rx - _x1) * _dx) + ((_ry - _y1) * _dy)) / _len_sq;
        _proj = clamp(_proj, 0, 1);

        var _bthr;
        if (_is_hires) {
            _bthr = (_bayer_hr[(_ry mod 8) * 8 + (_rx mod 8)] + 0.5) / 64;
        } else {
            var _mc_x = (_rx div 2) mod 4;
            var _mc_y = _ry mod 8;
            _bthr = (_bayer_mc[_mc_y * 4 + _mc_x] + 0.5) / 32;
        }

        // Which segment of the stop run does this projection fall in, and
        // how far across it (0..1) — that fraction is what gets dithered.
        var _seg = _proj * (_n_stops - 1);
        var _seg_idx = floor(_seg);
        if (_seg_idx > _last_seg) _seg_idx = _last_seg;
        if (_seg_idx < 0) _seg_idx = 0;
        var _seg_frac = _seg - _seg_idx;
        var _use_hi = (_seg_frac >= _bthr);
        var _pick = _use_hi ? (_seg_idx + 1) : _seg_idx;

        var _wr = _stop_r[_pick], _wg = _stop_g[_pick], _wb = _stop_b[_pick];
        var _wcol = _stops[_pick];

        var _o = (_ry * 320 + _rx) * 4;
        buffer_poke(_buf, _o,     buffer_u8, _wr);
        buffer_poke(_buf, _o + 1, buffer_u8, _wg);
        buffer_poke(_buf, _o + 2, buffer_u8, _wb);
        _asset.meta.bg_mask[_ry * 320 + _rx] = 1;

        if (_is_hires) {
            // Role follows which of the cell's 2 allowed colours (fg =
            // active_color, bg = anything else) landed on this pixel — same
            // fg/bg convention scr_asset_bmp_draw_line/_rect/_ellipse use.
            // HiRes hard-limits to 2 colours per 8x8 cell, so a custom stop
            // run with 3+ distinct colours landing in one cell is a genuine
            // clash — same as manually painting too many colours by hand —
            // and gets caught by the existing needs_clash_check/clash_grid
            // pass after this fill commits, same as any other tool.
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
