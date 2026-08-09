/// @function scr_vbmp_replay_to_surface(_asset)
/// Rebuilds _asset.meta.preview_surf from scratch by replaying meta.commands.
/// The preview is a pure function of the command list — call this after ANY
/// change (add / delete / reorder / undo) and the surface always matches what
/// the C64 will replay. Selector colours (0-3) map to the 4 palette slots.
function scr_vbmp_replay_to_surface(_asset) {
    var _m = _asset.meta;

    // Ensure surface exists at 320x200
    if (!variable_struct_exists(_m, "preview_surf") || !surface_exists(_m.preview_surf)) {
        _m.preview_surf = surface_create(320, 200);
    }

    // Resolve the 4 palette slots to real C64 colour indices.
    var _bg   = variable_struct_exists(_m, "bg")   ? _m.bg   : 0;
    var _col1 = variable_struct_exists(_m, "col1") ? _m.col1 : 1;
    var _col2 = variable_struct_exists(_m, "col2") ? _m.col2 : 2;
    var _col3 = variable_struct_exists(_m, "col3") ? _m.col3 : 3;
    // Selector index (0-3) -> real colour lookup
    var _sel_to_col = [_bg, _col1, _col2, _col3];

    // Clear surface to background colour
    surface_set_target(_m.preview_surf);
    var _prev_filter = gpu_get_texfilter();
    gpu_set_texfilter(false);
    draw_clear(scr_c64_pepto_colour(_bg));
    surface_reset_target();

    // KLA-compat fields the shared draw routines read — ensure present
    if (!variable_struct_exists(_m, "bg_mask"))       _m.bg_mask = array_create(64000, 0);
    if (!variable_struct_exists(_m, "dither_mode"))   _m.dither_mode = "NONE";
    if (!variable_struct_exists(_m, "dither_invert")) _m.dither_invert = false;
    if (!variable_struct_exists(_m, "brush_size"))    _m.brush_size = 0;

    var _commands = variable_struct_exists(_m, "commands") ? _m.commands : [];

    // Shared pixel buffer for the whole replay. The cheap primitives
    // (line/rect/ellipse/plot) poke straight into this instead of each doing
    // their own surface round-trip — that round-trip was the frame's biggest
    // cost. It is loaded from the surface once here, flushed back once at the
    // very end, and temporarily synced around the read-back cases (fill /
    // ellipsefill / copyregion / recolour) which must see the live surface.
    var _shared_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_shared_buf, _m.preview_surf, 0);
    // True while _shared_buf holds pokes not yet flushed to the surface.
    var _buf_dirty = false;

    // Active selector while walking (SETCOL sets it; default 1)
    var _active_sel = 1;
    // Active dither pattern (SETPAT). For now maps to dither_mode NONE/CHECKER/etc.
    // Stage 1 editor keeps this simple — pattern index reserved for later.

    // Per-cell live colour map, walked in stream order so recolour overrides
    // land BEFORE any later copyregion reads them (matching the C64, where the
    // $08/$09 pokes precede the $0B copy). Init to the page globals.
    var _cell_c1 = array_create(40 * 25, _col1);
    var _cell_c2 = array_create(40 * 25, _col2);
    var _cell_c3 = array_create(40 * 25, _col3);

    for (var _ci = 0; _ci < array_length(_commands); _ci++) {
        var _cmd = _commands[_ci];
        if (!is_struct(_cmd) || !variable_struct_exists(_cmd, "op")) continue;
        var _op = string(_cmd.op);

        switch (_op) {
            case "setcol": {
                _active_sel = variable_struct_exists(_cmd, "col") ? (real(_cmd.col) & 0x03) : 1;
            } break;

            case "setpat": {
                // Reserved: pattern index -> dither. Stage 1 leaves dither NONE.
                // A later pass maps _cmd.pat to _m.dither_mode before the next primitive.
            } break;

            case "plot": {
                var _px = variable_struct_exists(_cmd, "x") ? (real(_cmd.x) div 2) * 2 : 0;
                var _py = variable_struct_exists(_cmd, "y") ? real(_cmd.y) : 0;
                var _col_idx = _sel_to_col[_active_sel];
                // Single MC pair via a zero-length line (reuses proven plot path)
                scr_asset_bmp_draw_line(_asset, _px, _py, _px, _py, _col_idx, 1, _shared_buf);
                _buf_dirty = true;
            } break;

            case "line": {
                var _x0 = variable_struct_exists(_cmd, "x0") ? real(_cmd.x0) : 0;
                var _y0 = variable_struct_exists(_cmd, "y0") ? real(_cmd.y0) : 0;
                var _x1 = variable_struct_exists(_cmd, "x1") ? real(_cmd.x1) : 0;
                var _y1 = variable_struct_exists(_cmd, "y1") ? real(_cmd.y1) : 0;
                scr_asset_bmp_draw_line(_asset, _x0, _y0, _x1, _y1, _sel_to_col[_active_sel], 1, _shared_buf);
                _buf_dirty = true;
            } break;

            case "rect": {
                var _x0 = variable_struct_exists(_cmd, "x0") ? real(_cmd.x0) : 0;
                var _y0 = variable_struct_exists(_cmd, "y0") ? real(_cmd.y0) : 0;
                var _x1 = variable_struct_exists(_cmd, "x1") ? real(_cmd.x1) : 0;
                var _y1 = variable_struct_exists(_cmd, "y1") ? real(_cmd.y1) : 0;
                var _rlx = min(_x0, _x1), _rrx = max(_x0, _x1);
                var _rty = min(_y0, _y1), _rby = max(_y0, _y1);
                scr_asset_bmp_draw_rect(_asset, _rlx, _rty, _rrx, _rby, _sel_to_col[_active_sel], 1, false, _shared_buf);
                _buf_dirty = true;
            } break;

            case "rectfill": {
                var _x0 = variable_struct_exists(_cmd, "x0") ? real(_cmd.x0) : 0;
                var _y0 = variable_struct_exists(_cmd, "y0") ? real(_cmd.y0) : 0;
                var _x1 = variable_struct_exists(_cmd, "x1") ? real(_cmd.x1) : 0;
                var _y1 = variable_struct_exists(_cmd, "y1") ? real(_cmd.y1) : 0;
                var _flx = min(_x0, _x1), _frx = max(_x0, _x1);
                var _fty = min(_y0, _y1), _fby = max(_y0, _y1);
                scr_asset_bmp_draw_rect(_asset, _flx, _fty, _frx, _fby, _sel_to_col[_active_sel], 1, true, _shared_buf);
                _buf_dirty = true;
            } break;

            case "ellipse": {
                var _cx = variable_struct_exists(_cmd, "cx") ? real(_cmd.cx) : 0;
                var _cy = variable_struct_exists(_cmd, "cy") ? real(_cmd.cy) : 0;
                var _rx = variable_struct_exists(_cmd, "rx") ? real(_cmd.rx) : 1;
                var _ry = variable_struct_exists(_cmd, "ry") ? real(_cmd.ry) : 1;
                // draw_ellipse takes a bounding box; rx is in MC units (x/4), so
                // the box half-width in hi-res px is rx*2. Reconstruct x1/x2/y1/y2.
                scr_asset_bmp_draw_ellipse(_asset, _cx - _rx * 2, _cy - _ry, _cx + _rx * 2, _cy + _ry, _sel_to_col[_active_sel], 1, false, _shared_buf);
                _buf_dirty = true;
            } break;

            case "ellipsefill": {
                // Flush pending shared-buffer pokes to the surface so this
                // read-back op composites over the current image.
                if (_buf_dirty) {
                    buffer_set_surface(_shared_buf, _m.preview_surf, 0);
                    _buf_dirty = false;
                }
                var _cx = variable_struct_exists(_cmd, "cx") ? real(_cmd.cx) : 0;
                var _cy = variable_struct_exists(_cmd, "cy") ? real(_cmd.cy) : 0;
                var _rx = variable_struct_exists(_cmd, "rx") ? real(_cmd.rx) : 1;
                var _ry = variable_struct_exists(_cmd, "ry") ? real(_cmd.ry) : 1;
                // Match the C64 $06 EXACTLY: for py = 0..ry the half-width is
                // xoff = (CIRCLE_Y[py*96/ry] * rx) >> 8, span drawn from -xoff to
                // +xoff in MC units at cy+py and cy-py. Painted unconditionally
                // (direct buffer poke, ONE buffer) so it is order-independent and
                // fills over any dither underneath — no flood, no seed dependency.
                if (surface_exists(_m.preview_surf)) {
                    var _ef_col = scr_c64_pepto_colour(_sel_to_col[_active_sel]);
                    var _ef_cr = color_get_red(_ef_col);
                    var _ef_cg = color_get_green(_ef_col);
                    var _ef_cb = color_get_blue(_ef_col);
                    var _ef_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    buffer_get_surface(_ef_buf, _m.preview_surf, 0);
                    var _ef_ryc = max(1, _ry);
                    var _ef_rxc = max(1, _rx);
                    for (var _py = 0; _py <= _ef_ryc; _py++) {
                        // idx = py*96/ry, rounded to match div16_ry's +ry/2 bias.
                        var _idx = floor((_py * 96 + (_ef_ryc div 2)) / _ef_ryc);
                        if (_idx > 96) _idx = 96;
                        // CIRCLE_Y[idx] = round(sqrt(1-(idx/96)^2)*255), same table.
                        var _norm = sqrt(max(0, 1 - (_idx / 96) * (_idx / 96)));
                        var _cyv  = round(_norm * 255);
                        if (_cyv > 255) _cyv = 255;
                        // xoff = (cyv*rx)>>8
                        var _xoff = (_cyv * _ef_rxc) >> 8;
                        // two mirrored rows: cy+py and cy-py
                        var _rows = [_cy + _py, _cy - _py];
                        for (var _ri = 0; _ri < 2; _ri++) {
                            var _yy = _rows[_ri];
                            if (_yy < 0 || _yy >= 200) continue;
                            var _row_base = _yy * 320;
                            for (var _mc = -_xoff; _mc <= _xoff; _mc++) {
                                var _xx = (real(_cx + _mc * 2) div 2) * 2;
                                if (_xx < 0 || _xx > 318) continue;
                                var _woff = (_row_base + _xx) * 4;
                                buffer_poke(_ef_buf, _woff,     buffer_u8, _ef_cr);
                                buffer_poke(_ef_buf, _woff + 1, buffer_u8, _ef_cg);
                                buffer_poke(_ef_buf, _woff + 2, buffer_u8, _ef_cb);
                                buffer_poke(_ef_buf, _woff + 4, buffer_u8, _ef_cr);
                                buffer_poke(_ef_buf, _woff + 5, buffer_u8, _ef_cg);
                                buffer_poke(_ef_buf, _woff + 6, buffer_u8, _ef_cb);
                                _m.bg_mask[_row_base + _xx]     = 1;
                                _m.bg_mask[_row_base + _xx + 1] = 1;
                            }
                        }
                    }
                    buffer_set_surface(_ef_buf, _m.preview_surf, 0);
                    buffer_delete(_ef_buf);
                }
                // Reload the shared buffer from the surface this op just wrote,
                // so later cheap primitives keep poking a current image.
                buffer_get_surface(_shared_buf, _m.preview_surf, 0);
            } break;

            case "fill": {
                if (_buf_dirty) {
                    buffer_set_surface(_shared_buf, _m.preview_surf, 0);
                    _buf_dirty = false;
                }
                var _fx = variable_struct_exists(_cmd, "x") ? (real(_cmd.x) div 2) * 2 : 0;
                var _fy = variable_struct_exists(_cmd, "y") ? real(_cmd.y) : 0;
                var _fpat  = variable_struct_exists(_cmd, "pattern") ? real(_cmd.pattern) : 0;
                var _fcolb = variable_struct_exists(_cmd, "colb")    ? real(_cmd.colb)    : 0;
                if (_fpat == 0) {
                    // Solid fill — single flood, existing helper.
                    _m.dither_mode = "NONE";
                    scr_asset_bmp_flood_fill(_asset, _fx, _fy, _sel_to_col[_active_sel]);
                } else {
                    // Dither fill — ONE parity flood painting colA/colB per pixel,
                    // matching the C64 vbmp_fill runtime exactly. No pre-fill pass,
                    // so colB may equal bg / outline / colA with no special-casing.
                    scr_vbmp_flood_dither(_asset, _fx, _fy, _sel_to_col[_active_sel], _sel_to_col[_fcolb], _fpat);
                }
                buffer_get_surface(_shared_buf, _m.preview_surf, 0);
            } break;

            case "polyline": {
                if (variable_struct_exists(_cmd, "pts") && is_array(_cmd.pts)) {
                    var _pts = _cmd.pts;
                    for (var _pi = 0; _pi < array_length(_pts) - 1; _pi++) {
                        var _pa = _pts[_pi];
                        var _pb = _pts[_pi + 1];
                        scr_asset_bmp_draw_line(_asset, _pa[0], _pa[1], _pb[0], _pb[1], _sel_to_col[_active_sel], 1, _shared_buf);
                    }
                    _buf_dirty = true;
                }
            } break;

            case "polyfill": {
                // Stage 3: proper scanline polygon fill. For now draw the outline
                // so the primitive is at least visible in the editor.
                if (variable_struct_exists(_cmd, "pts") && is_array(_cmd.pts)) {
                    var _pts = _cmd.pts;
                    var _n = array_length(_pts);
                    for (var _pi = 0; _pi < _n; _pi++) {
                        var _pa = _pts[_pi];
                        var _pb = _pts[(_pi + 1) mod _n];
                        scr_asset_bmp_draw_line(_asset, _pa[0], _pa[1], _pb[0], _pb[1], _sel_to_col[_active_sel], 1, _shared_buf);
                    }
                    _buf_dirty = true;
                }
            } break;
			
			case "copyregion": {
                if (_buf_dirty) {
                    buffer_set_surface(_shared_buf, _m.preview_surf, 0);
                    _buf_dirty = false;
                }
                // True visual copy in the preview by copying the composited RGB
                // block from the source cell rect to the dest cell rect. This
                // replay bakes every command (including recolour) straight onto
                // preview_surf in stream order, so the surface already holds the
                // final colour for each source cell — copying the pixels carries
                // shape AND colour, including any recolour that ran earlier in
                // the stream. Reads come only from a snapshot (_cr_src) taken
                // before any write, so an overlapping dest can't corrupt a
                // still-to-be-read source pixel within this one command.
                if (surface_exists(_m.preview_surf)) {
                    var _cr_sc = clamp(variable_struct_exists(_cmd, "sc") ? real(_cmd.sc) : 0, 0, 39);
                    var _cr_sr = clamp(variable_struct_exists(_cmd, "sr") ? real(_cmd.sr) : 0, 0, 24);
                    var _cr_dc = clamp(variable_struct_exists(_cmd, "dc") ? real(_cmd.dc) : 0, 0, 39);
                    var _cr_dr = clamp(variable_struct_exists(_cmd, "dr") ? real(_cmd.dr) : 0, 0, 24);
                    var _cr_w  = clamp(variable_struct_exists(_cmd, "w")  ? real(_cmd.w)  : 1, 1, 40);
                    var _cr_h  = clamp(variable_struct_exists(_cmd, "h")  ? real(_cmd.h)  : 1, 1, 25);
                    if (_cr_sc + _cr_w > 40) _cr_w = 40 - _cr_sc;
                    if (_cr_dc + _cr_w > 40) _cr_w = 40 - _cr_dc;
                    if (_cr_sr + _cr_h > 25) _cr_h = 25 - _cr_sr;
                    if (_cr_dr + _cr_h > 25) _cr_h = 25 - _cr_dr;

                    var _cr_pw  = _cr_w * 8;
                    var _cr_ph  = _cr_h * 8;
                    var _cr_spx = _cr_sc * 8;
                    var _cr_spy = _cr_sr * 8;
                    var _cr_dpx = _cr_dc * 8;
                    var _cr_dpy = _cr_dr * 8;

                    var _cr_src = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    var _cr_dst = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    buffer_get_surface(_cr_src, _m.preview_surf, 0);
                    buffer_copy(_cr_src, 0, 320 * 200 * 4, _cr_dst, 0);

                    var _yy = 0;
                    repeat (_cr_ph) {
                        var _sy = _cr_spy + _yy;
                        var _dy = _cr_dpy + _yy;
                        if (_sy >= 0 && _sy < 200 && _dy >= 0 && _dy < 200) {
                            var _srowb = _sy * 320;
                            var _drowb = _dy * 320;
                            var _xx = 0;
                            repeat (_cr_pw) {
                                var _sx = _cr_spx + _xx;
                                var _dx = _cr_dpx + _xx;
                                if (_sx >= 0 && _sx < 320 && _dx >= 0 && _dx < 320) {
                                    var _so  = (_srowb + _sx) * 4;
                                    var _doo = (_drowb + _dx) * 4;
                                    buffer_poke(_cr_dst, _doo,     buffer_u8, buffer_peek(_cr_src, _so,     buffer_u8));
                                    buffer_poke(_cr_dst, _doo + 1, buffer_u8, buffer_peek(_cr_src, _so + 1, buffer_u8));
                                    buffer_poke(_cr_dst, _doo + 2, buffer_u8, buffer_peek(_cr_src, _so + 2, buffer_u8));
                                    buffer_poke(_cr_dst, _doo + 3, buffer_u8, buffer_peek(_cr_src, _so + 3, buffer_u8));
                                }
                                _xx += 1;
                            }
                        }
                        _yy += 1;
                    }

                    buffer_set_surface(_cr_dst, _m.preview_surf, 0);
                    buffer_delete(_cr_src);
                    buffer_delete(_cr_dst);
                }
                buffer_get_surface(_shared_buf, _m.preview_surf, 0);
            } break;

            case "recolor_cram":
            case "recolor_sram": {
                if (_buf_dirty) {
                    buffer_set_surface(_shared_buf, _m.preview_surf, 0);
                    _buf_dirty = false;
                }
                // Poke-equivalent: RGB-substitute OLD colour for NEW across the
                // affected 8x8 cells, updating the per-cell colour map. Runs in
                // stream order so a copyregion later in the stream copies the
                // recoloured pixels — exactly as the C64 $08/$09 then $0B does.
                if (surface_exists(_m.preview_surf)) {
                    var _rcol = clamp(variable_struct_exists(_cmd, "col") ? real(_cmd.col) : 0, 0, 39);
                    var _rrow = clamp(variable_struct_exists(_cmd, "row") ? real(_cmd.row) : 0, 0, 24);
                    var _rw   = clamp(variable_struct_exists(_cmd, "w")   ? real(_cmd.w)   : 1, 1, 40);
                    var _rh   = clamp(variable_struct_exists(_cmd, "h")   ? real(_cmd.h)   : 1, 1, 25);
                    if (_rcol + _rw > 40) _rw = 40 - _rcol;
                    if (_rrow + _rh > 25) _rh = 25 - _rrow;

                    var _rbuf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    buffer_get_surface(_rbuf, _m.preview_surf, 0);

                    for (var _cyr = _rrow; _cyr < _rrow + _rh; _cyr++) {
                        for (var _cxr = _rcol; _cxr < _rcol + _rw; _cxr++) {
                            var _cidx = _cyr * 40 + _cxr;

                            var _subs = [];
                            if (_op == "recolor_cram") {
                                var _n3 = (variable_struct_exists(_cmd, "c3") ? real(_cmd.c3) : 0) & 0x0F;
                                array_push(_subs, [scr_c64_pepto_colour(_cell_c3[_cidx]), scr_c64_pepto_colour(_n3)]);
                                _cell_c3[_cidx] = _n3;
                            } else {
                                var _n1 = (variable_struct_exists(_cmd, "c1") ? real(_cmd.c1) : 1) & 0x0F;
                                var _n2 = (variable_struct_exists(_cmd, "c2") ? real(_cmd.c2) : 2) & 0x0F;
                                array_push(_subs, [scr_c64_pepto_colour(_cell_c1[_cidx]), scr_c64_pepto_colour(_n1)]);
                                array_push(_subs, [scr_c64_pepto_colour(_cell_c2[_cidx]), scr_c64_pepto_colour(_n2)]);
                                _cell_c1[_cidx] = _n1;
                                _cell_c2[_cidx] = _n2;
                            }

                            var _ns = array_length(_subs);
                            var _or = array_create(_ns), _og = array_create(_ns), _ob = array_create(_ns);
                            var _nr = array_create(_ns), _ng = array_create(_ns), _nb = array_create(_ns);
                            for (var _si = 0; _si < _ns; _si++) {
                                _or[_si] = color_get_red(_subs[_si][0]);
                                _og[_si] = color_get_green(_subs[_si][0]);
                                _ob[_si] = color_get_blue(_subs[_si][0]);
                                _nr[_si] = color_get_red(_subs[_si][1]);
                                _ng[_si] = color_get_green(_subs[_si][1]);
                                _nb[_si] = color_get_blue(_subs[_si][1]);
                            }

                            var _bpx0 = _cxr * 8;
                            var _bpy0 = _cyr * 8;
                            for (var _yy = _bpy0; _yy < _bpy0 + 8; _yy++) {
                                if (_yy < 0 || _yy >= 200) continue;
                                var _rowb = _yy * 320;
                                for (var _xx = _bpx0; _xx < _bpx0 + 8; _xx++) {
                                    if (_xx < 0 || _xx >= 320) continue;
                                    var _po  = (_rowb + _xx) * 4;
                                    var _pcr = buffer_peek(_rbuf, _po,     buffer_u8);
                                    var _pcg = buffer_peek(_rbuf, _po + 1, buffer_u8);
                                    var _pcb = buffer_peek(_rbuf, _po + 2, buffer_u8);
                                    for (var _si = 0; _si < _ns; _si++) {
                                        if (_pcr == _or[_si] && _pcg == _og[_si] && _pcb == _ob[_si]) {
                                            buffer_poke(_rbuf, _po,     buffer_u8, _nr[_si]);
                                            buffer_poke(_rbuf, _po + 1, buffer_u8, _ng[_si]);
                                            buffer_poke(_rbuf, _po + 2, buffer_u8, _nb[_si]);
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    buffer_set_surface(_rbuf, _m.preview_surf, 0);
                    buffer_delete(_rbuf);
                }
                buffer_get_surface(_shared_buf, _m.preview_surf, 0);
            } break;

            default: break;
        }
    }

    // Flush any trailing cheap-primitive pokes and release the shared buffer.
    if (_buf_dirty) {
        buffer_set_surface(_shared_buf, _m.preview_surf, 0);
    }
    buffer_delete(_shared_buf);

    gpu_set_texfilter(_prev_filter);
}