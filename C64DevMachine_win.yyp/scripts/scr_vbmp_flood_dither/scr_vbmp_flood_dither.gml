/// @function scr_vbmp_flood_dither(_asset, _start_x, _start_y, _colA_idx, _colB_idx, _pattern)
/// Preview-only parity flood matching the C64 vbmp_fill runtime EXACTLY. One
/// flood identifies the connected region (seed-colour matched, MC 2px steps);
/// every reached pixel is painted colA or colB by pixel parity — both colours
/// explicit, neither tied to the target. So colB may equal the background, the
/// outline, or colA with no special-casing (unlike the old pre-fill-then-flood
/// approach in scr_asset_bmp_flood_fill, which can only paint fillcol OR leave
/// the target colour).
///   _pattern: 1 = checker  parity = ((x>>1) + y) & 1   (matches vbmp_fp_dith)
///             2 = interlace parity = (y & 1)
/// Parity 0 -> colA, parity 1 -> colB.
function scr_vbmp_flood_dither(_asset, _start_x, _start_y, _colA_idx, _colB_idx, _pattern) {
    var _m = _asset.meta;
    if (!surface_exists(_m.preview_surf)) return;
    _start_x = (_start_x div 2) * 2; // MC snap

    var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _m.preview_surf, 0);

    var _colA = scr_c64_pepto_colour(_colA_idx);
    var _colB = scr_c64_pepto_colour(_colB_idx);
    var _ar = color_get_red(_colA), _ag = color_get_green(_colA), _ab = color_get_blue(_colA);
    var _br = color_get_red(_colB), _bg = color_get_green(_colB), _bb = color_get_blue(_colB);

    // Seed colour = the target the flood matches.
    var _off0 = (_start_y * 320 + _start_x) * 4;
    var _tr = buffer_peek(_buf, _off0,     buffer_u8);
    var _tg = buffer_peek(_buf, _off0 + 1, buffer_u8);
    var _tb = buffer_peek(_buf, _off0 + 2, buffer_u8);

    // If the seed already equals BOTH dither colours, the region can never
    // change — bail (mirrors the runtime's degenerate guard). If it equals
    // only one, the flood still needs to run to lay the other-parity pixels.
    var _seed_is_A = (_tr == _ar && _tg == _ag && _tb == _ab);
    var _seed_is_B = (_tr == _br && _tg == _bg && _tb == _bb);
    if (_seed_is_A && _seed_is_B) {
        buffer_delete(_buf);
        return;
    }

// PASS 1 — identify the connected region into _visited[], matching the
    // SEED colour only. Nothing is painted here, so painted pixels can never
    // block the spread (the bug that strangled a single-pass parity flood: a
    // colB pixel stops matching the seed and walls off the scanline). This
    // mirrors the C64 vbmp_fill, which captures the target once ($E3) and
    // never re-reads the painted result while spreading.
    var _stack = ds_stack_create();
    ds_stack_push(_stack, _start_x, _start_y);
    var _visited = array_create(320 * 200, false);

    while (!ds_stack_empty(_stack)) {
        var _cy = ds_stack_pop(_stack);
        var _cx = ds_stack_pop(_stack);

        if (_cx < 0 || _cx > 318 || _cy < 0 || _cy >= 200) continue;
        if (_visited[_cy * 320 + _cx]) continue;

        var _off = (_cy * 320 + _cx) * 4;
        if (buffer_peek(_buf, _off,     buffer_u8) != _tr) continue;
        if (buffer_peek(_buf, _off + 1, buffer_u8) != _tg) continue;
        if (buffer_peek(_buf, _off + 2, buffer_u8) != _tb) continue;

        // Scan left to the run start (MC steps), matching seed only.
        var _lx = _cx;
        while (_lx - 2 >= 0) {
            var _lo = (_cy * 320 + _lx - 2) * 4;
            if (buffer_peek(_buf, _lo,     buffer_u8) != _tr) break;
            if (buffer_peek(_buf, _lo + 1, buffer_u8) != _tg) break;
            if (buffer_peek(_buf, _lo + 2, buffer_u8) != _tb) break;
            _lx -= 2;
        }

        // Mark rightward, still matching seed only. NO painting yet.
        var _x = _lx;
        while (_x <= 318) {
            var _o = (_cy * 320 + _x) * 4;
            if (buffer_peek(_buf, _o,     buffer_u8) != _tr) break;
            if (buffer_peek(_buf, _o + 1, buffer_u8) != _tg) break;
            if (buffer_peek(_buf, _o + 2, buffer_u8) != _tb) break;

            _visited[_cy * 320 + _x]     = true;
            _visited[_cy * 320 + _x + 1] = true; // mark the MC pair partner too

            if (_cy > 0)   ds_stack_push(_stack, _x, _cy - 1);
            if (_cy < 199) ds_stack_push(_stack, _x, _cy + 1);
            _x += 2;
        }
    }

    ds_stack_destroy(_stack);

    // PASS 2 — paint the marked region colA/colB by parity. Reads only
    // _visited[], never the buffer, so parity pixels can't interfere with
    // each other. Parity EXACTLY matches vbmp_fp_dith on the C64.
    for (var _py = 0; _py < 200; _py++) {
        var _rowb = _py * 320;
        for (var _px = 0; _px <= 318; _px += 2) {
            if (!_visited[_rowb + _px]) continue;

            var _par;
            if (_pattern == 2) {
                _par = _py & 1;                    // interlace: y & 1
            } else {
                _par = ((_px div 2) + _py) & 1;    // checker: (x>>1 + y) & 1
            }
            var _wr = (_par == 0) ? _ar : _br;
            var _wg = (_par == 0) ? _ag : _bg;
            var _wb = (_par == 0) ? _ab : _bb;

            var _o = (_rowb + _px) * 4;
            buffer_poke(_buf, _o,     buffer_u8, _wr);
            buffer_poke(_buf, _o + 1, buffer_u8, _wg);
            buffer_poke(_buf, _o + 2, buffer_u8, _wb);
            buffer_poke(_buf, _o + 4, buffer_u8, _wr);
            buffer_poke(_buf, _o + 5, buffer_u8, _wg);
            buffer_poke(_buf, _o + 6, buffer_u8, _wb);
            _m.bg_mask[_rowb + _px]     = 1;
            _m.bg_mask[_rowb + _px + 1] = 1;
        }
    }

    // Skip the old shared-tail destroy (pass 1 already destroyed the stack).
    buffer_set_surface(_buf, _m.preview_surf, 0);
    buffer_delete(_buf);
    exit;

}