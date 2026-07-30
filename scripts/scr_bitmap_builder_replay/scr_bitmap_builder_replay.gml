/// @function scr_bitmap_builder_replay(_asset)
/// @desc Rebuilds the builder's scratch preview surface: seeds it from the
///       destination bitmap, then replays the records from prev_entry until
///       the first END ($FF) terminator — exactly what MOVE_BMP_BLOCK does at
///       runtime when handed this table with that entry index.
///
/// The KLA preview surface is already fully-resolved RGB. A cell-rect pixel
/// copy from src to dst is therefore equivalent to the runtime's
/// "copy bitmap + copy screen RAM + copy colour RAM" with BOTH palette planes
/// ON. That is the builder's assumption, and the editor warns if the node it
/// feeds has them switched off.
///
/// SOLID  — straight clobber (node BLEND = OPAQUE).
/// MASKED — source %00 pairs are holes; dest shows through. On a resolved RGB
///          surface that means "source pixels equal to the SOURCE bitmap's
///          background colour are transparent".
function scr_bitmap_builder_replay(_asset) {
    var _m = _asset.meta;

    // Free any stale scratch surface, make a fresh one.
    if (surface_exists(_m.prev_surf)) {
        surface_free(_m.prev_surf);
    }
    _m.prev_surf = surface_create(320, 200);

    // ── Resolve the two linked BITMAP assets ──
    var _src = noone;
    var _dst = noone;
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type != "BITMAP") {
                continue;
            }
            if (_a.name == _m.src_asset) {
                _src = _a;
            }
            if (_a.name == _m.dst_asset) {
                _dst = _a;
            }
        }
    }

    // ── Seed the scratch from the DEST bitmap (or black if none) ──
    surface_set_target(_m.prev_surf);
    gpu_set_texfilter(false);
    draw_clear(c_black);
    if (_dst != noone
    &&  variable_struct_exists(_dst.meta, "preview_surf")
    &&  surface_exists(_dst.meta.preview_surf)) {
        gpu_set_blendmode_ext(bm_one, bm_zero);
        draw_surface(_dst.meta.preview_surf, 0, 0);
        gpu_set_blendmode(bm_normal);
    }
    surface_reset_target();

    // No source, nothing to replay.
    if (_src == noone) {
        return;
    }
    if (!variable_struct_exists(_src.meta, "preview_surf")) {
        return;
    }
    if (!surface_exists(_src.meta.preview_surf)) {
        return;
    }

    // ── Pull both planes into buffers for per-pixel work ──
    var _sbuf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_sbuf, _src.meta.preview_surf, 0);
    var _dbuf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_dbuf, _m.prev_surf, 0);

    // MASKED transparency key = the SOURCE bitmap's background colour.
    var _src_bg  = variable_struct_exists(_src.meta, "bg_col") ? _src.meta.bg_col : 0;
    var _key_col = scr_c64_pepto_colour(_src_bg);
    var _key_r   = color_get_red(_key_col);
    var _key_g   = color_get_green(_key_col);
    var _key_b   = color_get_blue(_key_col);

    var _masked = (_m.blend == 1);

    // ── MASK00 hole detection, per source cell ──
    // The runtime treats two kinds of source pixel as a hole: background, and
    // whichever painted colour covers the fewest pixels in that cell. The
    // second rule exists because a merged cell can carry only three colours
    // plus background — dropping the sparsest guarantees a free slot for a
    // destination colour to occupy, so the dest shows through rather than being
    // approximated. See scr_mbb_emit_mask_cells.
    //
    // On a resolved RGB surface a cell's distinct non-background colours ARE
    // its palette slots, so the same decision can be made by tallying pixels
    // without reconstructing screen or colour RAM. Results are cached per cell
    // for the duration of this replay — a cell grabbed by several records is
    // scanned once.


    // ── Walk the GROUP that contains prev_entry ──
    // prev_entry is a selection cursor into the record list, not a start point.
    // A group is everything between two $FF sentinels, so rewind from the
    // cursor to the record after the preceding END, then play forward to the
    // next one. Clicking any record in a group therefore previews that whole
    // group — which is exactly what the runtime draws when handed the group's
    // index — rather than a partial run starting mid-way through it.
    var _total = array_length(_m.records);
    var _cur   = clamp(_m.prev_entry, 0, max(0, _total - 1));

    // A cursor parked ON a sentinel is the group that sentinel CLOSES, so step
    // back into it — UNLESS that group is empty, i.e. the slot behind the
    // sentinel is another sentinel (or there is nothing behind it at all). An
    // empty group has no records, so stepping back would land on the PREVIOUS
    // group's last record and replay that group instead of showing a blank
    // canvas. Leaving _cur on the sentinel makes the forward walk below stop
    // immediately, which is exactly right: nothing to draw.
    if (_cur < _total) {
        if (_m.records[_cur].kind == "END") {
            var _empty_grp = true;
            if (_cur > 0) {
                if (_m.records[_cur - 1].kind != "END") {
                    _empty_grp = false;
                }
            }
            if (!_empty_grp) {
                _cur = _cur - 1;
            }
        }
    }

    var _ri = _cur;
    while (_ri > 0) {
        if (_m.records[_ri - 1].kind == "END") {
            break;
        }
        _ri -= 1;
    }

    while (_ri < _total) {
        var _rec = _m.records[_ri];
        if (_rec.kind == "END") {
            break;
        }

        // Cell rect -> pixel rect. Clamp so a bad record can't walk off-canvas.
        var _sx0 = clamp(_rec.sx * 8, 0, 319);
        var _sy0 = clamp(_rec.sy * 8, 0, 199);
        var _dx0 = clamp(_rec.dx * 8, 0, 319);
        var _dy0 = clamp(_rec.dy * 8, 0, 199);
        var _pw  = _rec.w * 8;
        var _ph  = _rec.h * 8;

        for (var _py = 0; _py < _ph; _py++) {
            var _syy = _sy0 + _py;
            var _dyy = _dy0 + _py;
            if (_syy < 0 || _syy > 199) {
                continue;
            }
            if (_dyy < 0 || _dyy > 199) {
                continue;
            }
            for (var _px = 0; _px < _pw; _px++) {
                var _sxx = _sx0 + _px;
                var _dxx = _dx0 + _px;
                if (_sxx < 0 || _sxx > 319) {
                    continue;
                }
                if (_dxx < 0 || _dxx > 319) {
                    continue;
                }

                var _soff = (_syy * 320 + _sxx) * 4;
                var _r = buffer_peek(_sbuf, _soff,     buffer_u8);
                var _g = buffer_peek(_sbuf, _soff + 1, buffer_u8);
                var _b = buffer_peek(_sbuf, _soff + 2, buffer_u8);

                // MASKED: only background (source %00) is a hole. The runtime's
                // sparsest-slot drop frees a PALETTE slot but still paints those
                // pixels from the source byte, so on this resolved surface the
                // pixel is kept — matching what MOVE_BMP_BLOCK now emits.
                if (_masked) {
                    if (_r == _key_r && _g == _key_g && _b == _key_b) {
                        continue;
                    }
                }

                var _doff = (_dyy * 320 + _dxx) * 4;
                buffer_poke(_dbuf, _doff,     buffer_u8, _r);
                buffer_poke(_dbuf, _doff + 1, buffer_u8, _g);
                buffer_poke(_dbuf, _doff + 2, buffer_u8, _b);
                buffer_poke(_dbuf, _doff + 3, buffer_u8, 255);
            }
        }

        _ri += 1;
    }


    buffer_set_surface(_dbuf, _m.prev_surf, 0);
    buffer_delete(_dbuf);
    buffer_delete(_sbuf);
}