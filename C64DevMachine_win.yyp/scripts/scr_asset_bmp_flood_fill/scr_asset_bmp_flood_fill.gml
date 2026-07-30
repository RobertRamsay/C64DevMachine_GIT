/// @function scr_asset_bmp_flood_fill(_asset, _start_x, _start_y, _col_idx, _mask_val, _hr_fg)
/// @param {Bool} _hr_fg HiRes only: true = this fill sets the cell's fg role/colour, false = bg role/colour.
function scr_asset_bmp_flood_fill(_asset, _start_x, _start_y, _col_idx, _mask_val = 1, _hr_fg = false) {
    if (!surface_exists(_asset.meta.preview_surf)) return;
    var _is_hires = scr_asset_bmp_is_hires(_asset);
    var _step     = _is_hires ? 1 : 2;
    var _max_x    = _is_hires ? 319 : 318;
    if (!_is_hires) _start_x = (_start_x div 2) * 2; // MC snap

    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _asset.meta.preview_surf, 0);

    var _new_col  = scr_c64_pepto_colour(_col_idx);
    var _nr = color_get_red(_new_col), _ng = color_get_green(_new_col), _nb = color_get_blue(_new_col);

    // Build a 16-entry C64 RGB-to-index hash for fast target colour lookups during dither bookkeeping
    var _color_hash = {};
    for (var _ci = 0; _ci < 16; _ci++) {
        var _cc = scr_c64_pepto_colour(_ci);
        _color_hash[$ (color_get_red(_cc) << 16) | (color_get_green(_cc) << 8) | color_get_blue(_cc)] = _ci;
    }

    // Read target colour from start pixel.
    var _off0 = (_start_y * 320 + _start_x) * 4;
    var _tr = buffer_peek(_buf, _off0,     buffer_u8);
    var _tg = buffer_peek(_buf, _off0 + 1, buffer_u8);
    var _tb = buffer_peek(_buf, _off0 + 2, buffer_u8);

    // Already that colour — nothing to do.
    if (_tr == _nr && _tg == _ng && _tb == _nb) {
        buffer_delete(_buf);
        return;
    }

    // Cache dither settings once — they don't change during the fill.
    var _dmode = _asset.meta.dither_mode;
    var _dinv  = _asset.meta.dither_invert;
    var _do_dither = false;
    if (_dmode != "NONE") {
        _do_dither = true;
    } else {
        _do_dither = false;
    }

    // Run-based scanline flood. The stack holds one seed (x,y) per contiguous
    // run discovered on the row above/below, NOT one entry per pixel — this
    // collapses thousands of stack ops into dozens.
    //
    // A colour-only "already filled" test is NOT enough once dithering is in
    // play: a dithered pixel that lands on the "keep original colour" side
    // (_use_new == false) gets written back to its OWN original colour, so it
    // still matches _tr/_tg/_tb forever. Every neighbouring row then keeps
    // re-discovering and re-queuing it as "still unfilled" with no bound —
    // that unbounded re-queuing is what hung the program on the coarser
    // Bayer patterns. _visited tracks "this pixel has been processed" purely
    // by position, independent of what colour dithering gave it, so every
    // pixel is queued and walked exactly once regardless.
    var _visited = array_create(64000, false);
    var _stack = ds_stack_create();
    ds_stack_push(_stack, _start_x, _start_y);

    while (!ds_stack_empty(_stack)) {
        var _cy = ds_stack_pop(_stack);
        var _cx = ds_stack_pop(_stack);

        if (_cx < 0 || _cx > _max_x || _cy < 0 || _cy >= 200) continue;
        if (_visited[_cy * 320 + _cx]) continue;

        // The seed pixel may already be filled (another run reached it first),
        // so re-test it before doing any work.
        var _soff = (_cy * 320 + _cx) * 4;
        if (buffer_peek(_buf, _soff,     buffer_u8) != _tr) continue;
        if (buffer_peek(_buf, _soff + 1, buffer_u8) != _tg) continue;
        if (buffer_peek(_buf, _soff + 2, buffer_u8) != _tb) continue;

        // Scan left to the leftmost matching, not-yet-visited pixel (or MC
        // pixel-pair) in this run.
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

            // Decide fill colour for this pixel/pair (dither picks new or target).
            var _use_new = true;
            if (_do_dither) {
                _use_new = scr_check_dither_mask(_dmode, _x, _cy, _is_hires);
                if (_dinv) {
                    _use_new = !_use_new;
                }
            }
            var _wr, _wg, _wb;
            if (_use_new) {
                _wr = _nr; _wg = _ng; _wb = _nb;
            } else {
                _wr = _tr; _wg = _tg; _wb = _tb;
            }
            buffer_poke(_buf, _o,     buffer_u8, _wr);
            buffer_poke(_buf, _o + 1, buffer_u8, _wg);
            buffer_poke(_buf, _o + 2, buffer_u8, _wb);
            _asset.meta.bg_mask[_cy * 320 + _x] = _mask_val;
            if (_is_hires) {
                var _hrcf = (floor(_cy / 8) * 40) + floor(_x / 8);
                // Dithering can leave THIS pixel at either the new fill colour
                // (_use_new) or the original target colour it already had — the
                // role/colour bookkeeping must match whichever actually landed,
                // not blindly assume every touched pixel took the fill role.
                // No whole-cell repaint here: the buffer_poke above already
                // wrote the correct final colour for this exact pixel, and the
                // flood fill naturally visits every matching pixel in a solid
                // region on its own, so the dithered pattern is already
                // correct in the buffer — repainting the whole cell to 2 solid
                // colours would erase that per-pixel variation entirely.
                if (_use_new) {
                    _asset.meta.hr_role_mask[_cy * 320 + _x] = _hr_fg ? 1 : 0;
                    if (_hr_fg) { _asset.meta.hr_cell_fg_col[_hrcf] = _col_idx; }
                    else        { _asset.meta.hr_cell_bg_col[_hrcf] = _col_idx; }
                } else {
                    var _target_idx = _color_hash[$ (_tr << 16) | (_tg << 8) | _tb];
                    if (_target_idx == undefined) _target_idx = 0;
                    _asset.meta.hr_role_mask[_cy * 320 + _x] = _hr_fg ? 0 : 1;
                    if (_hr_fg) { _asset.meta.hr_cell_bg_col[_hrcf] = _target_idx; }
                    else        { _asset.meta.hr_cell_fg_col[_hrcf] = _target_idx; }
                }
            } else {
                buffer_poke(_buf, _o + 4, buffer_u8, _wr);
                buffer_poke(_buf, _o + 5, buffer_u8, _wg);
                buffer_poke(_buf, _o + 6, buffer_u8, _wb);
                _asset.meta.bg_mask[_cy * 320 + _x + 1] = _mask_val;
            }

            // Row above: seed once per entered span. Must also require
            // !visited — otherwise a dithered "kept-colour" pixel that was
            // already processed on a previous pass keeps re-triggering a
            // fresh seed here forever.
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

            // Row below: seed once per entered span. Same !visited guard.
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
    buffer_set_surface(_buf, _asset.meta.preview_surf, 0);
    buffer_delete(_buf);
}